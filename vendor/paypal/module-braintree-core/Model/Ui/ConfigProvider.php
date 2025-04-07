<?php
/**
 * Copyright © Magento, Inc. All rights reserved.
 * See COPYING.txt for license details.
 */
namespace PayPal\Braintree\Model\Ui;

use Braintree\Result\Error;
use Braintree\Result\Successful;
use Magento\Framework\HTTP\PhpEnvironment\RemoteAddress;
use PayPal\Braintree\Gateway\Request\PaymentDataBuilder;
use Magento\Checkout\Model\ConfigProviderInterface;
use PayPal\Braintree\Gateway\Config\Config;
use PayPal\Braintree\Gateway\Config\PayPal\Config as PayPalConfig;
use PayPal\Braintree\Model\Adapter\BraintreeAdapter;
use Magento\Framework\Exception\InputException;
use Magento\Framework\Exception\NoSuchEntityException;
use Magento\Payment\Model\CcConfig;
use Magento\Framework\View\Asset\Source;

class ConfigProvider implements ConfigProviderInterface
{
    public const CODE = 'braintree';
    public const CC_VAULT_CODE = 'braintree_cc_vault';

    /**
     * @var PayPalConfig
     */
    private PayPalConfig $paypalConfig;

    /**
     * @var Config
     */
    private Config $config;

    /**
     * @var BraintreeAdapter
     */
    private BraintreeAdapter $adapter;

    /**
     * @var string
     */
    private string $clientToken = '';

    /**
     * @var CcConfig
     */
    private CcConfig $ccConfig;

    /**
     * @var Source
     */
    private Source $assetSource;

    /**
     * @var array
     */
    private array $icons = [];

    /**
     * @var RemoteAddress
     */
    private RemoteAddress $remoteAddress;

    /**
     * ConfigProvider constructor.
     *
     * @param Config $config
     * @param PayPalConfig $payPalConfig
     * @param BraintreeAdapter $adapter
     * @param CcConfig $ccConfig
     * @param Source $assetSource
     * @param RemoteAddress $remoteAddress
     */
    public function __construct(
        Config $config,
        PayPalConfig $payPalConfig,
        BraintreeAdapter $adapter,
        CcConfig $ccConfig,
        Source $assetSource,
        RemoteAddress $remoteAddress
    ) {
        $this->config = $config;
        $this->adapter = $adapter;
        $this->paypalConfig = $payPalConfig;
        $this->ccConfig = $ccConfig;
        $this->assetSource = $assetSource;
        $this->remoteAddress = $remoteAddress;
    }

    /**
     * @inheritDoc
     */
    public function getConfig(): array
    {
        if (!$this->config->isActive()) {
            return [];
        }

        $config = [
            'payment' => [
                self::CODE => [
                    'isActive' => $this->config->isActive(),
                    'clientToken' => $this->getClientToken(),
                    'ccTypesMapper' => $this->config->getCcTypesMapper(),
                    'countrySpecificCardTypes' => $this->config->getCountrySpecificCardTypeConfig(),
                    'availableCardTypes' => $this->config->getAvailableCardTypes(),
                    'useCvv' => $this->config->isCvvEnabled(),
                    'environment' => $this->config->getEnvironment(),
                    'merchantId' => $this->config->getMerchantId(),
                    'ccVaultCode' => self::CC_VAULT_CODE,
                    'style' => [
                        'shape' => $this->paypalConfig->getButtonShape(PayPalConfig::BUTTON_AREA_CHECKOUT),
                        'size' => $this->paypalConfig->getButtonSize(PayPalConfig::BUTTON_AREA_CHECKOUT),
                        'color' => $this->paypalConfig->getButtonColor(PayPalConfig::BUTTON_AREA_CHECKOUT)
                    ],
                    'disabledFunding' => [
                        'card' => $this->paypalConfig->isFundingOptionCardDisabled(),
                        'elv' => $this->paypalConfig->isFundingOptionElvDisabled()
                    ],
                    'icons' => $this->getIcons()
                ],
                Config::CODE_3DSECURE => [
                    'enabled' => $this->config->isVerify3DSecure(),
                    'challengeRequested' => $this->config->is3DSAlwaysRequested(),
                    'thresholdAmount' => $this->config->getThresholdAmount(),
                    'specificCountries' => $this->config->get3DSecureSpecificCountries(),
                    'ipAddress' => $this->remoteAddress->getRemoteAddress()
                ]
            ]
        ];

        return $config;
    }

    /**
     * Generate a new client token if necessary
     *
     * @return Error|Successful|string|null
     * @throws InputException
     * @throws NoSuchEntityException
     */
    public function getClientToken(): Error|Successful|string|null
    {
        if (empty($this->clientToken)) {
            $params = [];

            $merchantAccountId = $this->config->getMerchantAccountId();
            if (!empty($merchantAccountId)) {
                $params[PaymentDataBuilder::MERCHANT_ACCOUNT_ID] = $merchantAccountId;
            }

            $this->clientToken = $this->adapter->generate($params);
        }

        return $this->clientToken;
    }

    /**
     * Get icons for available payment methods
     *
     * @return array
     */
    public function getIcons(): array
    {
        if (!empty($this->icons)) {
            return $this->icons;
        }

        $types = $this->ccConfig->getCcAvailableTypes();
        $types['NONE'] = '';

        foreach (array_keys($types) as $code) {
            if (!array_key_exists($code, $this->icons)) {
                $asset = $this->ccConfig->createAsset('PayPal_Braintree::images/cc/' . strtoupper($code) . '.png');
                if ($asset) {
                    $placeholder = $this->assetSource->findSource($asset);
                    if ($placeholder) {
                        list($width, $height) = getimagesizefromstring($asset->getSourceFile());
                        $this->icons[$code] = [
                            'url' => $asset->getUrl(),
                            'width' => $width,
                            'height' => $height
                        ];
                    }
                }
            }
        }

        return $this->icons;
    }
}

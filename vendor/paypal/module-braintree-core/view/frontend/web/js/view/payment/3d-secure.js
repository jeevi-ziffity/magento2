/**
 * Copyright © Magento, Inc. All rights reserved.
 * See COPYING.txt for license details.
 */
/*browser:true*/
/*global define*/

define([
    'jquery',
    'PayPal_Braintree/js/view/payment/adapter',
    'Magento_Checkout/js/model/quote',
    'mage/translate',
    'braintreeThreeDSecure',
    'Magento_Checkout/js/model/full-screen-loader'
], function ($, braintree, quote, $t, threeDSecure, fullScreenLoader) {
    'use strict';

    return {
        config: null,

        /**
         * Set 3d secure config
         * @param {Object} config
         */
        setConfig: function (config) {
            this.config = config;
            this.config.thresholdAmount = parseFloat(config.thresholdAmount);
        },

        /**
         * Get code
         * @returns {String}
         */
        getCode: function () {
            return 'three_d_secure';
        },

        /**
         * convert Non-ASCII characters into unicode
         *
         * @param str
         * @returns {string}
         */
        escapeNonAsciiCharacters: function (str) {
            return str.split('').map(function (c) {
                return /^[\x00-\x7F]$/.test(c) ? c : c.split('').map(function (a) {
                    return '\\u00' + a.charCodeAt(0).toString(16);
                }).join('');
            }).join('');
        },

        /**
         * Check billing/shipping address line lengths
         *
         * @param errorMessage
         * @param billingAddress
         * @param shippingAddress
         * @returns {*}
         */
        checkBillingLineLengths: function (errorMessage, billingAddress, shippingAddress) {
            let lineError = null;

            if (billingAddress.street[0].length > 50 ||
                (shippingAddress.street !== undefined && shippingAddress.street[0].length > 50)) {
                lineError = 'line1';
            } else if (billingAddress.street[1].length > 50 ||
                (shippingAddress.street !== undefined && shippingAddress.street[1].length > 50)) {
                lineError = 'line2';
            }

            if (lineError) {
                let error = `Billing/Shipping ${lineError} must be string and less than 50 characters.`;

                return $t(`${error} Please update the address and try again.`);
            }
        },

        /**
         * Validate Braintree payment nonce
         * @param {Object} context
         * @returns {Object}
         */
        validate: function (context) {
            let self = this,
                clientInstance = braintree.getApiClient(),
                state = $.Deferred(),
                totalAmount = parseFloat(quote.totals()['base_grand_total']).toFixed(2),
                billingAddress = quote.billingAddress(),
                shippingAddress = quote.shippingAddress(),
                setup3d;

            // Handle billing address region code
            if (billingAddress.regionCode == null) {
                billingAddress.regionCode = undefined;
            }
            if (billingAddress.regionCode !== undefined && billingAddress.regionCode.length > 2) {
                billingAddress.regionCode = undefined;
            }

            // Handle shipping address region code
            if (!quote.isVirtual()) {
                if (shippingAddress.regionCode == null) {
                    shippingAddress.regionCode = undefined;
                }
                if (shippingAddress.regionCode !== undefined && shippingAddress.regionCode.length > 2) {
                    shippingAddress.regionCode = undefined;
                }
            }

            // No 3d secure if using CVV verification on vaulted cards
            if (quote.paymentMethod().method.indexOf('braintree_cc_vault_') !== -1) {
                if (this.config.useCvvVault === true) {
                    state.resolve();
                    return state.promise();
                }
            }

            if (!this.isAmountAvailable(totalAmount) || !this.isCountryAvailable(billingAddress.countryId)) {
                state.resolve();
                return state.promise();
            }

            fullScreenLoader.startLoader();

            setup3d = function(clientInstance) {
                threeDSecure.create({
                    version: 2,
                    client: clientInstance
                }, function (threeDSecureErr, threeDSecureInstance) {
                    if (threeDSecureErr) {
                        fullScreenLoader.stopLoader();
                        return state.reject($t('Please try again with another form of payment.'));
                    }

                    let threeDSContainer = document.createElement('div'),
                        tdMask = document.createElement('div'),
                        tdFrame = document.createElement('div'),
                        tdBody = document.createElement('div'),
                        threeDSecureParameters;

                    threeDSContainer.id = 'braintree-three-d-modal';
                    tdMask.className ="bt-mask";
                    tdFrame.className ="bt-modal-frame";
                    tdBody.className ="bt-modal-body";

                    tdFrame.appendChild(tdBody);
                    threeDSContainer.appendChild(tdMask);
                    threeDSContainer.appendChild(tdFrame);

                    threeDSecureParameters = {
                        amount: totalAmount,
                        nonce: context.paymentMethodNonce,
                        bin: context.creditCardBin,
                        collectDeviceData: true,
                        challengeRequested: self.getChallengeRequested(),
                        billingAddress: {
                            givenName: self.escapeNonAsciiCharacters(billingAddress.firstname),
                            surname: self.escapeNonAsciiCharacters(billingAddress.lastname),
                            phoneNumber: billingAddress.telephone,
                            streetAddress: billingAddress.street[0],
                            extendedAddress: billingAddress.street[1],
                            locality: billingAddress.city,
                            region: billingAddress.regionCode,
                            postalCode: billingAddress.postcode,
                            countryCodeAlpha2: billingAddress.countryId
                        },
                        additionalInformation: {
                            ipAddress: self.getIpAddress()
                        },
                        onLookupComplete: function (data, next) {
                            next();
                        },
                        addFrame: function (err, iframe) {
                            fullScreenLoader.stopLoader();

                            if (err) {
                                console.log("Unable to verify card over 3D Secure", err);
                                return state.reject($t('Please try again with another form of payment.'));
                            }

                            tdBody.appendChild(iframe);
                            document.body.appendChild(threeDSContainer);
                        },
                        removeFrame: function () {
                            fullScreenLoader.startLoader();
                            document.body.removeChild(threeDSContainer);
                        }
                    };

                    if (context.hasOwnProperty('email') && context.email !== null) {
                        threeDSecureParameters.email = context.email;
                    }

                    if (!quote.isVirtual()) {
                        threeDSecureParameters.additionalInformation = {
                            shippingGivenName: self.escapeNonAsciiCharacters(shippingAddress.firstname),
                            shippingSurname: self.escapeNonAsciiCharacters(shippingAddress.lastname),
                            shippingAddress: {
                                streetAddress: shippingAddress.street[0],
                                extendedAddress: shippingAddress.street[1],
                                locality: shippingAddress.city,
                                region: shippingAddress.regionCode,
                                postalCode: shippingAddress.postcode,
                                countryCodeAlpha2: shippingAddress.countryId
                            },
                            shippingPhone: shippingAddress.telephone,
                            ipAddress: threeDSecureParameters.additionalInformation.ipAddress
                        }
                    }

                    threeDSecureInstance.verifyCard(threeDSecureParameters, function (err, response) {
                        fullScreenLoader.stopLoader();

                        if (err) {
                            console.error('3DSecure validation failed', err);
                            if (err.code === 'THREEDS_LOOKUP_VALIDATION_ERROR') {
                                let errorMessage = err.details.originalError.details.originalError.error.message,
                                    error = self.checkBillingLineLengths(errorMessage, billingAddress, shippingAddress);

                                return error ? state.reject(error) : state.reject($t(errorMessage));
                            }

                            return state.reject($t('Please try again with another form of payment.'));
                        }

                        let liability = {
                            shifted: response.liabilityShifted,
                            shiftPossible: response.liabilityShiftPossible
                        };

                        if (liability.shifted || !liability.shifted && !liability.shiftPossible) {
                            context.paymentMethodNonce = response.nonce;
                            state.resolve();
                        } else {
                            state.reject($t('Please try again with another form of payment.'));
                        }
                    });
                });
            };

            if (!clientInstance) {
                require(['PayPal_Braintree/js/view/payment/method-renderer/cc-form'], function (c) {
                    let config = c.extend({
                        defaults: {
                            clientConfig: {
                                onReady: function () {}
                            }
                        }
                    });

                    braintree.setConfig(config.defaults.clientConfig);
                    braintree.setup(setup3d);
                });
            } else {
                setup3d(clientInstance);
            }

            return state.promise();
        },

        /**
         * Check minimal amount for 3d secure activation
         * @param {Number} amount
         * @returns {Boolean}
         */
        isAmountAvailable: function (amount) {
            amount = parseFloat(amount.toString());

            return amount >= this.config.thresholdAmount;
        },

        /**
         * Check if current country is available for 3d secure
         * @param {String} countryId
         * @returns {Boolean}
         */
        isCountryAvailable: function (countryId) {
            let key,
                specificCountries = this.config.specificCountries;

            // all countries are available
            if (!specificCountries.length) {
                return true;
            }

            for (key in specificCountries) {
                if (countryId === specificCountries[key]) {
                    return true;
                }
            }

            return false;
        },

        /**
         * @returns {Boolean}
         */
        getChallengeRequested: function () {
            return this.config.challengeRequested;
        },

        /**
         * Get the Customer's IP Address
         *
         * @returns {*}
         */
        getIpAddress: function () {
            return this.config.ipAddress;
        }
    };
});

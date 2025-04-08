<?php
declare(strict_types=1);

namespace Preparation\CustomPage\Controller\Index;

use Magento\Framework\App\ActionInterface;
use Magento\Framework\Controller\ResultFactory;
use Magento\Framework\View\Result\PageFactory;

class Index implements ActionInterface
{
    /**
     * @var PageFactory
     */
    private $pageFactory;
    /**
     * @var ResultFactory
     */
    private $resultFactory;

    public function __construct(
        PageFactory $pageFactory,
        ResultFactory $resultFactory
    ) {
        $this->pageFactory = $pageFactory;
        $this->resultFactory = $resultFactory;
    }
    public function execute()
    {
        return $this->resultFactory->create(ResultFactory::TYPE_PAGE);
    }
}

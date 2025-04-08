<?php
declare(strict_types=1);

namespace Preparation\CustomPage\Block;

use Magento\Framework\View\Element\Template;

class Text extends Template
{
    /**
     * @return string
     */
    public function getMainText(): string
    {
        return 'Custom Main text';
    }

    public function getSubText(): string
    {
        return 'Custom Sub text';
    }
}

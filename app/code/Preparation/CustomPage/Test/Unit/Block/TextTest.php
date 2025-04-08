<?php
declare(strict_types=1);

namespace Preparation\CustomPage\Test\Unit\Block;

use PHPUnit\Framework\TestCase;
use Preparation\CustomPage\Block\Text;
use Magento\Framework\View\Element\Template\Context;

class TextTest extends TestCase
{
    /**
     * @var Text
     */
    protected $textBlock;

    /**
     * Set up test environment
     */
    protected function setUp(): void
    {
        $contextMock = $this->createMock(Context::class);
        $this->textBlock = new Text($contextMock);
    }

    public function testGetMainTextReturnsExpectedString(): void
    {
        $this->assertEquals('Custom Main text', $this->textBlock->getMainText());
    }
}

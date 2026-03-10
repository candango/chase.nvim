# PHP Runner

The PHP runner in Chase provides automated autoloading, include path management, and PHPUnit integration.

## 🚀 Activation Triggers

Chase identifies a PHP project if any of the following files are found in the project root:
- `composer.json`
- `composer.lock`
- `artisan`
- `phpunit.xml`
- `phpunit.xml.dist`
- `vendor/autoload.php`

## 🧪 Execution Logic

When you press `<leader>cc`:

- **Inside a Test**:
  - Uses **Tree-sitter** to detect `PHPUnit\Framework\TestCase` classes and methods.
  - Command: `vendor/bin/phpunit --filter "ClassName::methodName" <file>`
- **Outside a Test**:
  - Command: `php -d include_path='.:/project/root' -d auto_prepend_file='/project/root/vendor/autoload.php' <file>`
- **Autoloading**:
  - Automatically prepends `vendor/autoload.php` to any executed script if it exists.
  - Adds the project root to the PHP `include_path`.

## ⚙️ Configuration

```lua
require("chase").setup({
    php = {
        enabled = true,
        include_path = { "." },
    },
})
```

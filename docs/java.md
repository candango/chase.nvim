# Java Runner

The Java runner in Chase provides integrated testing and execution supporting Maven, Gradle, and standard Java.

## 🚀 Activation Triggers

Chase identifies a Java project if any of the following files are found in the project root:
- `.classpath`
- `pom.xml`
- `build.gradle`
- `build.gradle.kts`
- `settings.gradle`
- `settings.gradle.kts`

## 🧪 Execution Logic

When you press `<leader>cc`:

- **Inside a Test**:
  - Uses **Tree-sitter** to detect JUnit test methods.
  - **Maven**: `mvn test -Dtest=ClassName#methodName`
  - **Gradle**: `./gradlew test --tests ClassName#methodName`
- **Outside a Test**:
  - **Maven**: `mvn exec:java -Dexec.mainClass=ClassName`
  - **Gradle**: `./gradlew run`
  - **Standard Java**: Compiles with `javac` into `build/` and runs with `java -cp build/ ClassName`.

## ⚙️ Configuration

```lua
require("chase").setup({
    java = {
        enabled = true,
    },
})
```

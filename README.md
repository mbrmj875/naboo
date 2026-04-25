# Basra Store Manager

Flutter project for managing store operations.

## Build on Windows (Release)

Use these steps on the target Windows machine after copying this project:

1. Install Flutter SDK and Visual Studio with **Desktop development with C++**.
2. Open terminal in the project folder.
3. Run:

```bash
flutter pub get
flutter config --enable-windows-desktop
flutter build windows --release
```

4. The executable output will be created in:

```text
build\windows\x64\runner\Release\
```

## Notes

- Windows executable must be built on a Windows host.
- If packages change, run `flutter pub get` again before building.

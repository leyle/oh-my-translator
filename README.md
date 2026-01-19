# Oh-My-Translator

AI-powered translation tool for macOS with multi-provider support.

## Features

### Translation Modes
- **Translate** - Full text translation
- **Polish** - Improve writing style and grammar
- **Explain** - Context-aware word/phrase explanations with IPA pronunciation

### Multi-Provider Support
Works with any OpenAI-compatible API:
- OpenAI
- OpenRouter
- Vercel AI Gateway
- Any OpenAI-compatible endpoint

### Smart Features
- **Model-aware caching** - LRU cache that invalidates on model change
- **Auto re-request** - Automatically re-translates when you switch AI models
- **Word selection** - Click any word to get contextual explanations
- **Custom actions** - Create shell-script powered actions for selected text

### Integration
- **URL Scheme** (`omt://`) - Call from shell scripts, works whether app is running or not
- **Keyboard shortcut** - `Cmd+Enter` to translate
- **CLI args** - Pass text directly when launching

### UI/UX
- Clean macOS-native interface
- Dark mode support
- Persistent window size
- Drag-and-drop action reordering

## Requirements

- macOS 12.0+
- Flutter 3.x

## Build

```bash
# Clone the repository
git clone https://github.com/leyle/oh-my-translator.git
cd oh-my-translator

# Get dependencies
flutter pub get

# Build for macOS (debug)
flutter build macos --debug

# Build for macOS (release)
flutter build macos --release
```

The built app will be at:
- Debug: `build/macos/Build/Products/Debug/oh_my_translator.app`
- Release: `build/macos/Build/Products/Release/oh_my_translator.app`

## Usage

### From Shell Script

```bash
# Translate text from clipboard
./translate.sh

# Translate specific text
./translate.sh "Hello World"

# Translate to specific language
./translate.sh --to=ja "Hello World"
```

### URL Scheme

```bash
# Open with text (works if app is running or not)
open "omt://translate?text=Hello%20World"

# With target language
open "omt://translate?text=Hello%20World&to=zh"
```

### In-App
1. Enter or paste text in the input area
2. Select target language
3. Press `Cmd+Enter` or click Translate button
4. Click any word to get contextual explanation

## Configuration

Go to Settings (gear icon) to:
- Add AI providers (API key, base URL, model)
- Create custom actions with shell scripts
- Enable/disable providers

## Acknowledgments

This project was inspired by and learned from:

### [NextAI Translator](https://github.com/nextai-translator/nextai-translator)
A powerful AI translation tool built with Tauri. Studied its architecture for:
- Multi-provider API integration patterns
- Caching strategies for AI responses
- Clipboard and text selection handling on macOS

### [Kelivo](https://github.com/Chevey339/kelivo)
A Flutter-based AI chat application. Learned from its implementation of:
- Clean Flutter architecture and state management
- macOS-native UI patterns and dark mode support
- Streaming response handling for AI APIs

Thank you to both projects for inspiring the design and implementation of Oh-My-Translator!

## License

MIT

## Author

**leyle** - [GitHub](https://github.com/leyle)

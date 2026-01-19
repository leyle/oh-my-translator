import 'dart:io';

/// Executes shell scripts with text input
/// Based on Kelivo's pattern for selection actions
class ShellExecutor {
  /// Run a shell script with the given text as an argument
  /// 
  /// Parameters:
  /// - [scriptPath]: Path to the shell script (can be relative or absolute)
  /// - [inputText]: Text to pass as the first argument to the script
  /// 
  /// Returns the stdout from the script on success
  /// Throws [ShellExecutionException] on failure
  Future<String> execute(String scriptPath, String inputText) async {
    try {
      final result = await Process.run(
        scriptPath,
        [inputText],
        runInShell: true,
      );

      if (result.exitCode != 0) {
        final stderr = result.stderr.toString().trim();
        throw ShellExecutionException(
          message: stderr.isNotEmpty ? stderr : 'Script failed',
          exitCode: result.exitCode,
          scriptPath: scriptPath,
        );
      }

      return result.stdout.toString();
    } on ProcessException catch (e) {
      throw ShellExecutionException(
        message: e.message,
        exitCode: e.errorCode,
        scriptPath: scriptPath,
      );
    }
  }

  /// Execute a script and ignore the result (fire and forget)
  /// Useful for actions like TTS where we don't need the output
  Future<void> executeAsync(String scriptPath, String inputText) async {
    try {
      await Process.start(
        scriptPath,
        [inputText],
        runInShell: true,
        mode: ProcessStartMode.detached,
      );
    } catch (_) {
      // Ignore errors for fire-and-forget execution
    }
  }

  /// Check if a script exists and is executable
  Future<bool> isExecutable(String scriptPath) async {
    try {
      final file = File(scriptPath);
      if (!await file.exists()) return false;
      
      // On Unix systems, check if file is executable
      if (Platform.isMacOS || Platform.isLinux) {
        final stat = await file.stat();
        // Check if any execute bit is set
        return (stat.mode & 0x111) != 0;
      }
      
      return true;
    } catch (_) {
      return false;
    }
  }
}

/// Exception thrown when shell script execution fails
class ShellExecutionException implements Exception {
  final String message;
  final int exitCode;
  final String scriptPath;

  const ShellExecutionException({
    required this.message,
    required this.exitCode,
    required this.scriptPath,
  });

  @override
  String toString() => 'ShellExecutionException: $message (exit code: $exitCode, script: $scriptPath)';
}

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/models/provider_config.dart';
import '../../../core/models/custom_action.dart';
import '../../../core/providers/settings_provider.dart';
import '../../../core/services/engines/openai_compatible_engine.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        title: const Text('Settings'),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
        leadingWidth: 100, // Extra space to avoid overlap with window controls
        leading: Padding(
          padding: const EdgeInsets.only(left: 70), // Account for macOS traffic lights
          child: IconButton(
            icon: const Icon(LucideIcons.chevronLeft),
            onPressed: () => Navigator.pop(context),
          ),
        ),
      ),
      body: Consumer<SettingsProvider>(
        builder: (context, settings, _) {
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // AI Providers section
              _buildSectionHeader(context, 'AI Providers'),
              const SizedBox(height: 8),
              ...settings.providers.map((provider) => _buildProviderTile(context, provider, settings)),
              _buildAddButton(context, 'Add Provider', () => _addProvider(context)),
              
              const SizedBox(height: 24),
              
              // Custom Actions section
              _buildSectionHeader(context, 'Custom Actions'),
              const SizedBox(height: 8),
              if (settings.customActions.isNotEmpty)
                ReorderableListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: settings.customActions.length,
                  onReorder: (oldIndex, newIndex) {
                    settings.reorderActions(oldIndex, newIndex);
                  },
                  itemBuilder: (context, index) {
                    final action = settings.customActions[index];
                    return _buildActionTile(context, action, settings, key: ValueKey(action.id));
                  },
                ),
              _buildAddButton(context, 'Add Action', () => _addAction(context)),
              
              const SizedBox(height: 24),
              
              // About section
              _buildSectionHeader(context, 'About'),
              const SizedBox(height: 8),
              _buildAboutTile(context),
            ],
          );
        },
      ),
    );
  }

  Widget _buildSectionHeader(BuildContext context, String title) {
    final cs = Theme.of(context).colorScheme;
    return Text(
      title,
      style: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: cs.primary,
        letterSpacing: 0.5,
      ),
    );
  }

  Widget _buildProviderTile(BuildContext context, ProviderConfig provider, SettingsProvider settings) {
    final cs = Theme.of(context).colorScheme;
    final isDefault = settings.defaultProvider?.id == provider.id;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: provider.enabled 
              ? (isDefault ? cs.primaryContainer : cs.surfaceContainerHighest)
              : cs.surfaceContainerHighest.withOpacity(0.5),
          child: Icon(
            LucideIcons.bot,
            size: 20,
            color: provider.enabled 
                ? (isDefault ? cs.primary : cs.onSurface)
                : cs.onSurface.withOpacity(0.4),
          ),
        ),
        title: Text(
          provider.name,
          style: TextStyle(
            color: provider.enabled ? null : cs.onSurface.withOpacity(0.5),
          ),
        ),
        subtitle: Text(
          '${provider.model} • ${_formatUrl(provider.apiUrl)}',
          style: TextStyle(fontSize: 12, color: cs.onSurface.withOpacity(0.6)),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isDefault)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: cs.primary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  'Default',
                  style: TextStyle(fontSize: 11, color: cs.primary, fontWeight: FontWeight.w500),
                ),
              ),
            const SizedBox(width: 4),
            // Enable/Disable toggle
            Switch(
              value: provider.enabled,
              onChanged: (value) {
                settings.updateProvider(provider.copyWith(enabled: value));
              },
            ),
            PopupMenuButton<String>(
              icon: Icon(LucideIcons.ellipsisVertical, size: 18),
              onSelected: (value) {
                switch (value) {
                  case 'default':
                    settings.setDefaultProvider(provider.id);
                    break;
                  case 'edit':
                    _editProvider(context, provider);
                    break;
                  case 'delete':
                    settings.removeProvider(provider.id);
                    break;
                }
              },
              itemBuilder: (context) => [
                if (!isDefault)
                  const PopupMenuItem(value: 'default', child: Text('Set as Default')),
                const PopupMenuItem(value: 'edit', child: Text('Edit')),
                const PopupMenuItem(value: 'delete', child: Text('Delete')),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionTile(BuildContext context, CustomAction action, SettingsProvider settings, {Key? key}) {
    final cs = Theme.of(context).colorScheme;

    return Card(
      key: key,
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Drag handle at the front
            ReorderableDragStartListener(
              index: settings.customActions.indexOf(action),
              child: Icon(
                LucideIcons.gripVertical,
                size: 20,
                color: cs.onSurface.withOpacity(0.4),
              ),
            ),
            const SizedBox(width: 12),
            CircleAvatar(
              backgroundColor: cs.surfaceContainerHighest,
              child: Icon(
                _getIconForAction(action.iconName),
                size: 20,
                color: cs.onSurface,
              ),
            ),
          ],
        ),
        title: Text(action.name),
        subtitle: Text(
          action.scriptPath,
          style: TextStyle(fontSize: 12, color: cs.onSurface.withOpacity(0.6)),
          overflow: TextOverflow.ellipsis,
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Switch(
              value: action.enabled,
              onChanged: (value) {
                settings.updateAction(action.copyWith(enabled: value));
              },
            ),
            IconButton(
              icon: Icon(LucideIcons.pencil, size: 18),
              onPressed: () => _editAction(context, action),
              tooltip: 'Edit',
            ),
            IconButton(
              icon: Icon(LucideIcons.trash2, size: 18),
              onPressed: () => settings.removeAction(action.id),
              tooltip: 'Delete',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAddButton(BuildContext context, String label, VoidCallback onPressed) {
    final cs = Theme.of(context).colorScheme;

    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: Icon(LucideIcons.plus, size: 16),
      label: Text(label),
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(vertical: 12),
        side: BorderSide(color: cs.outline.withOpacity(0.3)),
      ),
    );
  }

  Widget _buildAboutTile(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(LucideIcons.languages, color: cs.primary),
                const SizedBox(width: 12),
                const Text(
                  'Oh-My-Translator',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Version 1.0.0',
              style: TextStyle(fontSize: 13, color: cs.onSurface.withOpacity(0.6)),
            ),
            const SizedBox(height: 4),
            Text(
              'AI-powered translation tool',
              style: TextStyle(fontSize: 13, color: cs.onSurface.withOpacity(0.6)),
            ),
            const SizedBox(height: 8),
            Text(
              'Author: leyle',
              style: TextStyle(fontSize: 12, color: cs.onSurface.withOpacity(0.5)),
            ),
            const SizedBox(height: 4),
            GestureDetector(
              onTap: () => _launchUrl('https://github.com/leyle/oh-my-translator'),
              child: Text(
                'github.com/leyle/oh-my-translator',
                style: TextStyle(
                  fontSize: 12, 
                  color: cs.primary,
                  decoration: TextDecoration.underline,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
  
  void _launchUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  String _formatUrl(String url) {
    return url.replaceAll('https://', '').replaceAll('/v1', '');
  }

  IconData _getIconForAction(String iconName) {
    switch (iconName) {
      case 'volume2': return LucideIcons.volume2;
      case 'languages': return LucideIcons.languages;
      case 'search': return LucideIcons.search;
      case 'sparkles': return LucideIcons.sparkles;
      case 'brain': return LucideIcons.brain;
      case 'terminal': return LucideIcons.terminal;
      case 'code': return LucideIcons.code;
      case 'clipboard': return LucideIcons.clipboard;
      case 'link': return LucideIcons.link;
      case 'upload': return LucideIcons.upload;
      case 'bookmark': return LucideIcons.bookmark;
      case 'zap': return LucideIcons.zap;
      case 'wand': return LucideIcons.wand;
      case 'briefcase': return LucideIcons.briefcase;
      case 'messageCircle': return LucideIcons.messageCircle;
      case 'share': return LucideIcons.share;
      case 'send': return LucideIcons.send;
      case 'external_link': return LucideIcons.externalLink;
      default: return LucideIcons.play;
    }
  }

  void _addProvider(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => const ProviderEditPage(existing: null),
      ),
    );
  }

  void _editProvider(BuildContext context, ProviderConfig provider) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => ProviderEditPage(existing: provider),
      ),
    );
  }

  void _addAction(BuildContext context) {
    final nameController = TextEditingController();
    final scriptController = TextEditingController();
    String selectedIcon = 'terminal';

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: const Text('Add Custom Action'),
              content: SizedBox(
                width: 400,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: nameController,
                      decoration: const InputDecoration(
                        labelText: 'Name',
                        hintText: 'e.g., Speak Text',
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: scriptController,
                      decoration: const InputDecoration(
                        labelText: 'Script Path',
                        hintText: '/path/to/script.sh',
                      ),
                    ),
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 8,
                      children: CustomAction.availableIcons.map((iconName) {
                        return ChoiceChip(
                          label: Icon(_getIconForAction(iconName), size: 16),
                          selected: selectedIcon == iconName,
                          onSelected: (_) {
                            setState(() => selectedIcon = iconName);
                          },
                        );
                      }).toList(),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () {
                    final settings = context.read<SettingsProvider>();
                    settings.addAction(CustomAction.create(
                      name: nameController.text,
                      scriptPath: scriptController.text,
                      iconName: selectedIcon,
                    ));
                    Navigator.pop(context);
                  },
                  child: const Text('Add'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _editAction(BuildContext context, CustomAction action) {
    final nameController = TextEditingController(text: action.name);
    final scriptController = TextEditingController(text: action.scriptPath);
    String selectedIcon = action.iconName;

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: const Text('Edit Custom Action'),
              content: SizedBox(
                width: 400,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: nameController,
                      decoration: const InputDecoration(
                        labelText: 'Name',
                        hintText: 'e.g., Speak Text',
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: scriptController,
                      decoration: const InputDecoration(
                        labelText: 'Script Path',
                        hintText: '/path/to/script.sh',
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Align(
                      alignment: Alignment.centerLeft,
                      child: Text('Icon', style: TextStyle(fontSize: 12)),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: CustomAction.availableIcons.map((iconName) {
                        final isSelected = selectedIcon == iconName;
                        return InkWell(
                          onTap: () => setState(() => selectedIcon = iconName),
                          borderRadius: BorderRadius.circular(8),
                          child: Container(
                            width: 48,
                            height: 48,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: isSelected
                                    ? Theme.of(context).colorScheme.primary
                                    : Theme.of(context).colorScheme.outline.withOpacity(0.3),
                                width: isSelected ? 2 : 1,
                              ),
                              color: isSelected
                                  ? Theme.of(context).colorScheme.primary.withOpacity(0.1)
                                  : null,
                            ),
                            child: Icon(
                              _getIconForAction(iconName),
                              size: 20,
                              color: isSelected
                                  ? Theme.of(context).colorScheme.primary
                                  : null,
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () {
                    final settings = context.read<SettingsProvider>();
                    settings.updateAction(action.copyWith(
                      name: nameController.text,
                      scriptPath: scriptController.text,
                      iconName: selectedIcon,
                    ));
                    Navigator.pop(context);
                  },
                  child: const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );
  }
}

/// Full-page provider editor (like Kelivo)
class ProviderEditPage extends StatefulWidget {
  final ProviderConfig? existing;

  const ProviderEditPage({super.key, this.existing});

  @override
  State<ProviderEditPage> createState() => _ProviderEditPageState();
}

class _ProviderEditPageState extends State<ProviderEditPage> {
  late TextEditingController _nameController;
  late TextEditingController _urlController;
  late TextEditingController _pathController;
  late TextEditingController _keyController;
  late TextEditingController _modelController;

  List<ModelInfo> _availableModels = [];
  List<String> _selectedModels = [];
  bool _isFetchingModels = false;
  bool _isTesting = false;
  String? _testResult;
  String? _fetchError;
  bool _enabled = true;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.existing?.name ?? '');
    _urlController = TextEditingController(text: widget.existing?.apiUrl ?? 'https://api.openai.com/v1');
    _pathController = TextEditingController(text: widget.existing?.apiPath ?? '/chat/completions');
    _keyController = TextEditingController(text: widget.existing?.apiKey ?? '');
    _modelController = TextEditingController(text: widget.existing?.model ?? '');
    _selectedModels = List.from(widget.existing?.selectedModels ?? []);
    _enabled = widget.existing?.enabled ?? true;
    
    // Add the main model to selected if not already there
    if (widget.existing?.model != null && 
        widget.existing!.model.isNotEmpty &&
        !_selectedModels.contains(widget.existing!.model)) {
      _selectedModels.add(widget.existing!.model);
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _urlController.dispose();
    _pathController.dispose();
    _keyController.dispose();
    _modelController.dispose();
    super.dispose();
  }

  ProviderConfig _buildTempProvider() {
    return ProviderConfig.create(
      name: _nameController.text,
      apiUrl: _urlController.text,
      apiPath: _pathController.text,
      apiKey: _keyController.text,
      model: _modelController.text,
    );
  }

  Future<void> _testConnection() async {
    if (_keyController.text.isEmpty) {
      setState(() => _testResult = '❌ API Key required');
      return;
    }

    setState(() {
      _isTesting = true;
      _testResult = null;
    });

    try {
      final engine = OpenAICompatibleEngine(config: _buildTempProvider());
      final success = await engine.testConnection();
      engine.dispose();
      
      setState(() {
        _isTesting = false;
        _testResult = success ? '✅ Connected successfully' : '❌ Connection failed';
      });
    } catch (e) {
      setState(() {
        _isTesting = false;
        _testResult = '❌ Error: $e';
      });
    }
  }

  Future<void> _fetchModels() async {
    if (_urlController.text.isEmpty || _keyController.text.isEmpty) {
      setState(() => _fetchError = 'Please enter API URL and API Key first');
      return;
    }

    setState(() {
      _isFetchingModels = true;
      _fetchError = null;
    });

    try {
      final engine = OpenAICompatibleEngine(config: _buildTempProvider());
      final models = await engine.fetchModels();
      engine.dispose();
      
      setState(() {
        _availableModels = models;
        _isFetchingModels = false;
        if (models.isEmpty) {
          _fetchError = 'No models found';
        }
      });
    } catch (e) {
      setState(() {
        _isFetchingModels = false;
        _fetchError = 'Failed to fetch: $e';
      });
    }
  }

  void _openModelPicker() {
    if (_availableModels.isEmpty) {
      _fetchModels().then((_) {
        if (_availableModels.isNotEmpty) {
          _showModelPickerDialog();
        }
      });
    } else {
      _showModelPickerDialog();
    }
  }

  void _showModelPickerDialog() {
    showDialog(
      context: context,
      builder: (context) => _ModelPickerDialog(
        availableModels: _availableModels,
        selectedModels: _selectedModels,
        onModelsSelected: (models) {
          setState(() {
            _selectedModels = models;
            if (models.isNotEmpty && _modelController.text.isEmpty) {
              _modelController.text = models.first;
            }
          });
        },
      ),
    );
  }

  void _save() {
    final settings = context.read<SettingsProvider>();
    
    // Ensure main model is in selected models
    if (_modelController.text.isNotEmpty && !_selectedModels.contains(_modelController.text)) {
      _selectedModels.insert(0, _modelController.text);
    }
    
    if (widget.existing == null) {
      settings.addProvider(ProviderConfig.create(
        name: _nameController.text,
        apiUrl: _urlController.text,
        apiPath: _pathController.text,
        apiKey: _keyController.text,
        model: _modelController.text,
        selectedModels: _selectedModels,
        enabled: _enabled,
      ));
    } else {
      settings.updateProvider(widget.existing!.copyWith(
        name: _nameController.text,
        apiUrl: _urlController.text,
        apiPath: _pathController.text,
        apiKey: _keyController.text,
        model: _modelController.text,
        selectedModels: _selectedModels,
        enabled: _enabled,
      ));
    }
    
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        title: Text(widget.existing == null ? 'Add Provider' : 'Edit Provider'),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          // Enable toggle in app bar
          Switch(
            value: _enabled,
            onChanged: (v) => setState(() => _enabled = v),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Name
          TextField(
            controller: _nameController,
            decoration: const InputDecoration(
              labelText: 'Name',
              hintText: 'e.g., OpenAI, OpenRouter',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),

          // API Key with Test button
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: TextField(
                  controller: _keyController,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'API Key',
                    hintText: 'Your API key',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                height: 56,
                child: FilledButton.tonal(
                  onPressed: _isTesting ? null : _testConnection,
                  child: _isTesting
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('Test'),
                ),
              ),
            ],
          ),
          if (_testResult != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                _testResult!,
                style: TextStyle(
                  fontSize: 13,
                  color: _testResult!.startsWith('✅') ? Colors.green : cs.error,
                ),
              ),
            ),
          const SizedBox(height: 16),

          // API Base URL
          TextField(
            controller: _urlController,
            decoration: const InputDecoration(
              labelText: 'API Base URL',
              hintText: 'https://api.openai.com/v1',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),

          // API Path
          TextField(
            controller: _pathController,
            decoration: const InputDecoration(
              labelText: 'API Path',
              hintText: '/chat/completions',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 24),

          // Models section header
          Row(
            children: [
              Text(
                'Models',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: cs.onSurface,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '${_selectedModels.length}',
                style: TextStyle(
                  fontSize: 14,
                  color: cs.onSurface.withOpacity(0.6),
                ),
              ),
              const Spacer(),
              IconButton(
                icon: Icon(LucideIcons.plus, size: 18),
                onPressed: _openModelPicker,
                tooltip: 'Add Model',
              ),
              FilledButton.icon(
                onPressed: _isFetchingModels ? null : _fetchModels,
                icon: _isFetchingModels 
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(LucideIcons.refreshCw, size: 16),
                label: const Text('Fetch'),
              ),
            ],
          ),
          if (_fetchError != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                _fetchError!,
                style: TextStyle(fontSize: 12, color: cs.error),
              ),
            ),
          if (_availableModels.isNotEmpty && _fetchError == null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                '${_availableModels.length} models available',
                style: TextStyle(fontSize: 12, color: cs.primary),
              ),
            ),
          const SizedBox(height: 8),

          // Primary model selector
          DropdownButtonFormField<String>(
            value: _selectedModels.contains(_modelController.text) ? _modelController.text : null,
            decoration: const InputDecoration(
              labelText: 'Primary Model',
              border: OutlineInputBorder(),
            ),
            isExpanded: true,
            items: _selectedModels.isEmpty 
                ? [DropdownMenuItem(value: _modelController.text, child: Text(_modelController.text))]
                : _selectedModels.map((m) => DropdownMenuItem(value: m, child: Text(m, overflow: TextOverflow.ellipsis))).toList(),
            onChanged: (value) {
              if (value != null) {
                setState(() => _modelController.text = value);
              }
            },
          ),
          const SizedBox(height: 8),

          // Selected models list
          if (_selectedModels.isNotEmpty)
            Card(
              child: Column(
                children: _selectedModels.map((model) {
                  final isPrimary = model == _modelController.text;
                  return ListTile(
                    dense: true,
                    leading: Icon(
                      isPrimary ? LucideIcons.star : LucideIcons.circle,
                      size: 16,
                      color: isPrimary ? cs.primary : cs.onSurface.withOpacity(0.4),
                    ),
                    title: Text(model, overflow: TextOverflow.ellipsis),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (!isPrimary)
                          IconButton(
                            icon: Icon(LucideIcons.star, size: 16),
                            onPressed: () => setState(() => _modelController.text = model),
                            tooltip: 'Set as Primary',
                          ),
                        IconButton(
                          icon: Icon(LucideIcons.minus, size: 16),
                          onPressed: () => setState(() {
                            _selectedModels.remove(model);
                            if (model == _modelController.text && _selectedModels.isNotEmpty) {
                              _modelController.text = _selectedModels.first;
                            }
                          }),
                          tooltip: 'Remove',
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ),
          
          const SizedBox(height: 24),

          // Save button
          FilledButton(
            onPressed: _save,
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
            child: Text(widget.existing == null ? 'Save' : 'Save Changes'),
          ),
        ],
      ),
    );
  }
}

/// Model picker dialog with search and grouping
class _ModelPickerDialog extends StatefulWidget {
  final List<ModelInfo> availableModels;
  final List<String> selectedModels;
  final void Function(List<String>) onModelsSelected;

  const _ModelPickerDialog({
    required this.availableModels,
    required this.selectedModels,
    required this.onModelsSelected,
  });

  @override
  State<_ModelPickerDialog> createState() => _ModelPickerDialogState();
}

class _ModelPickerDialogState extends State<_ModelPickerDialog> {
  late TextEditingController _searchController;
  late List<String> _selected;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController();
    _selected = List.from(widget.selectedModels);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Map<String, List<ModelInfo>> _groupModels() {
    final groups = <String, List<ModelInfo>>{};
    
    for (final model in widget.availableModels) {
      if (_searchQuery.isNotEmpty && 
          !model.id.toLowerCase().contains(_searchQuery.toLowerCase())) {
        continue;
      }
      
      // Extract group from model id (e.g., "gpt-4o" -> "gpt")
      String group = 'Other';
      if (model.id.startsWith('gpt')) {
        group = 'GPT';
      } else if (model.id.startsWith('text-embedding')) {
        group = 'Embeddings';
      } else if (model.id.startsWith('claude')) {
        group = 'Claude';
      } else if (model.id.startsWith('gemini')) {
        group = 'Gemini';
      } else if (model.id.contains('deepseek')) {
        group = 'DeepSeek';
      } else if (model.id.contains('qwen')) {
        group = 'Qwen';
      }
      
      groups.putIfAbsent(group, () => []).add(model);
    }
    
    return groups;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final groups = _groupModels();

    return Dialog(
      child: Container(
        width: 500,
        height: 600,
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Text(
                  'Select Models',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                ),
                const Spacer(),
                IconButton(
                  icon: Icon(LucideIcons.x),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Search box
            TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Type model name to filter',
                prefixIcon: Icon(LucideIcons.search, size: 18),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              ),
              onChanged: (v) => setState(() => _searchQuery = v),
            ),
            const SizedBox(height: 12),

            // Model list
            Expanded(
              child: ListView(
                children: groups.entries.map((entry) {
                  return ExpansionTile(
                    title: Text(entry.key),
                    initiallyExpanded: entry.key == 'GPT' || groups.length == 1,
                    children: entry.value.map((model) {
                      final isSelected = _selected.contains(model.id);
                      return ListTile(
                        dense: true,
                        leading: Icon(
                          isSelected ? LucideIcons.circleCheck : LucideIcons.circle,
                          size: 18,
                          color: isSelected ? cs.primary : cs.onSurface.withOpacity(0.4),
                        ),
                        title: Text(model.id, overflow: TextOverflow.ellipsis),
                        trailing: IconButton(
                          icon: Icon(
                            isSelected ? LucideIcons.minus : LucideIcons.plus,
                            size: 18,
                          ),
                          onPressed: () {
                            setState(() {
                              if (isSelected) {
                                _selected.remove(model.id);
                              } else {
                                _selected.add(model.id);
                              }
                            });
                          },
                        ),
                        onTap: () {
                          setState(() {
                            if (isSelected) {
                              _selected.remove(model.id);
                            } else {
                              _selected.add(model.id);
                            }
                          });
                        },
                      );
                    }).toList(),
                  );
                }).toList(),
              ),
            ),
            const SizedBox(height: 12),

            // Actions
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Text('${_selected.length} selected'),
                const Spacer(),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: () {
                    widget.onModelsSelected(_selected);
                    Navigator.pop(context);
                  },
                  child: const Text('Done'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

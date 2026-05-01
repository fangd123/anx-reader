import 'package:anx_reader/config/shared_preference_provider.dart';
import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/models/opds_catalog.dart';
import 'package:anx_reader/page/opds/opds_feed_page.dart';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

class OpdsCatalogPage extends StatefulWidget {
  const OpdsCatalogPage({super.key});

  @override
  State<OpdsCatalogPage> createState() => _OpdsCatalogPageState();
}

class _OpdsCatalogPageState extends State<OpdsCatalogPage> {
  List<OpdsCatalog> _catalogs = const [];

  @override
  void initState() {
    super.initState();
    _catalogs = Prefs().opdsCatalogs;
  }

  Future<void> _openCatalog(OpdsCatalog catalog) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => OpdsFeedPage(
          catalog: catalog,
          initialTitle: catalog.displayName,
        ),
      ),
    );
  }

  Future<void> _editCatalog({OpdsCatalog? catalog}) async {
    final nameController = TextEditingController(text: catalog?.name ?? '');
    final urlController = TextEditingController(text: catalog?.url ?? '');
    final usernameController =
        TextEditingController(text: catalog?.username ?? '');
    final passwordController =
        TextEditingController(text: catalog?.password ?? '');
    bool obscurePassword = true;
    String? errorText;

    final saved = await showDialog<OpdsCatalog>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            InputDecoration decoration(String label, {String? errorText}) {
              return InputDecoration(
                labelText: label,
                errorText: errorText,
                border: const OutlineInputBorder(),
              );
            }

            return AlertDialog(
              title: Text(
                catalog == null
                    ? L10n.of(context).opdsAddCatalog
                    : L10n.of(context).opdsEditCatalog,
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: nameController,
                      decoration:
                          decoration(L10n.of(context).opdsCatalogNameLabel),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: urlController,
                      keyboardType: TextInputType.url,
                      decoration: decoration(
                        L10n.of(context).opdsCatalogUrlLabel,
                        errorText: errorText,
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: usernameController,
                      decoration: decoration(
                        L10n.of(context).opdsCatalogUsernameLabel,
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: passwordController,
                      obscureText: obscurePassword,
                      decoration: decoration(
                        L10n.of(context).opdsCatalogPasswordLabel,
                      ).copyWith(
                        suffixIcon: IconButton(
                          onPressed: () {
                            setStateDialog(() {
                              obscurePassword = !obscurePassword;
                            });
                          },
                          icon: Icon(
                            obscurePassword
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: Text(L10n.of(context).commonCancel),
                ),
                TextButton(
                  onPressed: () {
                    final normalizedUrl =
                        _normalizeUrl(urlController.text.trim());
                    if (normalizedUrl == null) {
                      setStateDialog(() {
                        errorText = L10n.of(context).opdsCatalogInvalidUrl;
                      });
                      return;
                    }

                    final uri = Uri.parse(normalizedUrl);
                    final displayName = nameController.text.trim().isEmpty
                        ? (uri.host.isNotEmpty ? uri.host : normalizedUrl)
                        : nameController.text.trim();

                    Navigator.of(dialogContext).pop(
                      OpdsCatalog(
                        id: catalog?.id ?? const Uuid().v4(),
                        name: displayName,
                        url: normalizedUrl,
                        username: usernameController.text.trim(),
                        password: passwordController.text,
                      ),
                    );
                  },
                  child: Text(L10n.of(context).commonSave),
                ),
              ],
            );
          },
        );
      },
    );

    if (saved == null) {
      return;
    }

    setState(() {
      final nextCatalogs = [..._catalogs];
      final existingIndex =
          nextCatalogs.indexWhere((item) => item.id == saved.id);
      if (existingIndex >= 0) {
        nextCatalogs[existingIndex] = saved;
      } else {
        nextCatalogs.add(saved);
      }
      _catalogs = nextCatalogs;
    });
    Prefs().opdsCatalogs = _catalogs;
  }

  Future<void> _deleteCatalog(OpdsCatalog catalog) async {
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: Text(L10n.of(context).commonDelete),
            content: Text(
              L10n.of(context).opdsDeleteCatalogConfirm(catalog.displayName),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: Text(L10n.of(context).commonCancel),
              ),
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: Text(L10n.of(context).commonDelete),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed) {
      return;
    }

    setState(() {
      _catalogs = _catalogs.where((item) => item.id != catalog.id).toList();
    });
    Prefs().opdsCatalogs = _catalogs;
  }

  String? _normalizeUrl(String value) {
    if (value.isEmpty) {
      return null;
    }

    final normalized = value.contains('://') ? value : 'https://$value';
    final uri = Uri.tryParse(normalized);
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
      return null;
    }
    return uri.toString();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(L10n.of(context).opdsCatalogsTitle),
        actions: [
          IconButton(
            onPressed: () => _editCatalog(),
            icon: const Icon(Icons.add),
          ),
        ],
      ),
      body: _catalogs.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.public_outlined,
                      size: 52,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      L10n.of(context).opdsCatalogsEmpty,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      onPressed: () => _editCatalog(),
                      icon: const Icon(Icons.add),
                      label: Text(L10n.of(context).opdsAddCatalog),
                    ),
                  ],
                ),
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
              itemCount: _catalogs.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final catalog = _catalogs[index];
                return Card(
                  child: ListTile(
                    leading: const Icon(Icons.public_outlined),
                    title: Text(catalog.displayName),
                    subtitle: Text(catalog.url),
                    onTap: () => _openCatalog(catalog),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          onPressed: () => _editCatalog(catalog: catalog),
                          icon: const Icon(Icons.edit_outlined),
                          tooltip: L10n.of(context).commonEdit,
                        ),
                        IconButton(
                          onPressed: () => _deleteCatalog(catalog),
                          icon: const Icon(Icons.delete_outline),
                          tooltip: L10n.of(context).commonDelete,
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }
}

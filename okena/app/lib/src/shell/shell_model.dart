import 'package:flutter/material.dart';

/// The five destinations that earn a tab: the same ones as the web
/// navigation, laid out for the phone.
enum ShellTab {
  inicio(label: 'Início', icon: Icons.home_outlined, selectedIcon: Icons.home),
  arquivos(
    label: 'Arquivos',
    icon: Icons.folder_outlined,
    selectedIcon: Icons.folder,
  ),
  fotos(
    label: 'Fotos',
    icon: Icons.photo_library_outlined,
    selectedIcon: Icons.photo_library,
  ),
  mural(
    label: 'Mural',
    icon: Icons.list_alt_outlined,
    selectedIcon: Icons.list_alt,
  ),
  mais(label: 'Mais', icon: Icons.more_horiz, selectedIcon: Icons.more_horiz);

  const ShellTab({
    required this.label,
    required this.icon,
    required this.selectedIcon,
  });

  final String label;
  final IconData icon;
  final IconData selectedIcon;
}

/// The long tail of the web sidebar: everything that does not earn a tab of
/// its own, reachable through Mais.
enum MoreRoute {
  moradores(
    segment: 'moradores',
    label: 'Moradores',
    icon: Icons.people_outline,
  ),
  armazenamento(
    segment: 'armazenamento',
    label: 'Armazenamento',
    icon: Icons.storage_outlined,
  ),
  saude(segment: 'saude', label: 'Saúde', icon: Icons.monitor_heart_outlined),
  pedidos(
    segment: 'pedidos',
    label: 'Pedidos de acesso',
    icon: Icons.inbox_outlined,
  ),
  conta(segment: 'conta', label: 'Conta', icon: Icons.account_circle_outlined);

  const MoreRoute({
    required this.segment,
    required this.label,
    required this.icon,
  });

  final String segment;
  final String label;
  final IconData icon;
}

/// The shell's navigation, in a contract a screen can hold.
///
/// `go_router`'s [StatefulNavigationShell] owns the stacks and the selected
/// branch; this controller exposes the two gestures the Swift `ShellModel`
/// offered also to non-shell callers: open a tab, or open a Mais row in one
/// move (the tab and the route together).
final class ShellModel extends ChangeNotifier {
  ShellModel({required this.onOpenTab, required this.onOpenMore});

  final void Function(ShellTab tab) onOpenTab;
  final void Function(MoreRoute route) onOpenMore;

  bool _immersive = false;
  bool _disposed = false;

  /// Whether a feature is covering the tab chrome, such as the photo viewer.
  bool get immersive => _immersive;

  void setImmersive(bool value) {
    if (_disposed || _immersive == value) return;
    _immersive = value;
    notifyListeners();
  }

  /// Opens one of the shell's tabs.
  void open(ShellTab tab) => onOpenTab(tab);

  /// Opens a Mais row in one gesture: the tab and the route together, so the
  /// destination is on screen, not one tap behind.
  void openMore(MoreRoute route) => onOpenMore(route);

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

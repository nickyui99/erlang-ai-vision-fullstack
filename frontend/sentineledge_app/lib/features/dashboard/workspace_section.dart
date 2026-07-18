/// The console tabs, in sidebar/nav-bar order, each with the URL path segment
/// it maps to (`/console/<path>`). Kept separate from the heavy workspace UI so
/// routing can be loaded without downloading the dashboard implementation.
enum WorkspaceSection {
  cameras('cameras'),
  overview('overview'),
  agents('agents'),
  events('events'),
  settings('settings');

  const WorkspaceSection(this.path);

  final String path;

  int get tabIndex => index;

  static WorkspaceSection fromIndex(int index) =>
      values[index.clamp(0, values.length - 1)];
}

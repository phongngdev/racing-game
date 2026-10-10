Plan: Flutter UI Demo

Goal:
Create a simple multi-page Flutter UI demo for the racing controller project.
For now, focus only on UI and mock data. No backend, sensors, QR scanning, Bluetooth, or real game logic yet.

Structure:
lib/
  main.dart
  pages/
    connect_page.dart
    tuning_page.dart
    race_page.dart
    collision_page.dart
    result_page.dart

Navigation:
- Use Material 3 NavigationBar.
- Use IndexedStack to switch between pages and preserve each page's state.
- 5 tabs:
  1. Connect
  2. Tuning
  3. Race
  4. Collision
  5. Result

Requirements:
- Keep main.dart simple and only handle app theme + navigation.
- Each page must be implemented in its own file.
- Use mock/static data for all values.
- Follow the provided UI design as closely as practical.
- Use a dark racing-style theme with lime/green accent colors.
- Make the layout responsive enough to demo in Flutter Web.
- Race page should use a wide/landscape-style layout.
- Do not over-engineer architecture or state management yet.
- Prefer standard Flutter Material 3 widgets.

Implementation order:
1. Build navigation shell.
2. Create placeholder for all 5 pages.
3. Implement Connect page.
4. Implement Tuning page.
5. Implement Race HUD.
6. Implement Collision warning page.
7. Implement Result page.
8. Final visual cleanup and consistent styling.

Important:
This is currently a UI prototype for demonstration purposes.
Prioritize visual fidelity, clean code, and fast iteration over production architecture.

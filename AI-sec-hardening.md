For context, here is my current UI code (lib/main.dart), my backend service (lib/pia_service.dart), and my native activity layer (android/app/src/main/kotlin/com/exponentiallydigital/pia_wireguard_cfga/MainActivity.kt).

I am developing an open-source Flutter Android app called `pia-wireguard-cfga` that provisions Private Internet Access (PIA) WireGuard configurations. 

I need help refactoring my UI screen and native Android configuration to implement 5 critical security hardening improvements. Please provide the exact code modifications required for the following items:

1. REMOVE PERMANENT FILE SYSTEM STORAGE
Currently, the app saves the generated `.conf` file to the local disk device storage permanently. I want to remove permanent disk-write operations entirely. The generated config text should only be held as a volatile string variable in memory (`AppState`). When the user clicks the "Share" action button (using `share_plus`), it should pass the string via a transient runtime cache wrapper (e.g., using `XFile.fromData` or temporary memory stream blocks) so that a physical file only exists for the duration of the system Share Sheet pipeline, ensuring no persistent config artifact is left behind on storage.

2. IMPLEMENT A "CLEAR" ACTION BUTTON
Add a prominent "Clear" button to the UI layout. When tapped, it must:
- Clear the `TextEditingController` for both the username and password fields.
- Wipe out the displayed configuration text container on the screen.
- Explicitly overwrite any temporary credential string variables to empty strings (`""`) immediately to make them safely out-of-scope for the Dart Garbage Collector.
- Call `setState()` to refresh the UI view state.

3. HARDEN THE UI INPUT FIELDS
Review my credential `TextField` widgets. Ensure that:
- The username field has `autocorrect: false` and `enableSuggestions: false` to stop mobile keyboards from memorizing the username.
- The password field has `obscureText: true`, `autocorrect: false`, `enableSuggestions: false`, and `enableInteractiveSelection: false` (to completely disable selection controls like cut, copy, or paste, preventing background clipboard leakage).

4. AUTOMATIC SAFETY TIMEOUT TIMER & USER INTERACTION RESETS
Implement an automatic safety timeout system:
- When the app successfully generates a configuration text layout on screen, start a 3-minute countdown timer. Next to the "Clear" button, show a real-time countdown in seconds showing how long until the session auto-wipes.
- If the countdown reaches zero without manual intervention, automatically trigger the exact same session-wiping function defined in Step 2 to clear the screen UI and RAM variables.
- Ensure the code explicitly manages the lifecycle of the countdown `Timer`, including safely canceling it inside the widget's `dispose()` method to prevent unexpected memory retention or crashes if the view is destroyed while ticking.
- Wrap the main UI scaffold inside an activity tracking widget (such as a `GestureDetector` or `Listener`). Any touch or typing interaction by the user must automatically reset the safety timeout back to a full 3 minutes, preventing accidental screen wipes during active reading or sharing.

5. NATIVE ANDROID TASK-SWITCHER PREVIEW BLOCK (FLAG_SECURE)
Show me exactly what to change in my `android/app/src/main/kotlin/.../MainActivity.kt` file to enforce `WindowManager.LayoutParams.FLAG_SECURE`. This must completely block system-level screenshots inside the application boundaries and render the application preview blank/black when looking at it from the Android Recent Apps / Task Switcher view (to protect on-screen WireGuard PrivateKeys from background os collection).

Please provide the updated Flutter stateful widget UI code snippets along with the updated native Kotlin `MainActivity.kt` file structure. Keep the code clean, concise, and focused on production security.

Be very specific telling me exactly what code lines to change, what to add, and where to place them.
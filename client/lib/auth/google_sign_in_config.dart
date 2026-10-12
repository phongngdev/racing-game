/// Public OAuth client IDs from the Google Cloud project. These are not secrets.
const googleWebClientId =
    '748338507130-3e2qub4b3b2cmdpu77v26eoc9cfmrn1g.apps.googleusercontent.com';

/// Registered in Google Cloud for com.phongngdev.racinggame and its SHA-1 keys.
/// The Android plugin discovers this client from the installed app identity;
/// it uses [googleWebClientId] as the server audience when requesting ID tokens.
const googleAndroidClientId =
    '748338507130-0vhha7kbf9u2rk4krh99s4f1sejmp7se.apps.googleusercontent.com';

const googleIosClientId =
    '748338507130-r8dja78rh7f158kovb58eajg1g9jedj4.apps.googleusercontent.com';

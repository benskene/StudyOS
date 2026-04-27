# Firebase Setup Checklist (StudyOS)

1. Add Firebase iOS SDK via Swift Package Manager:
   - https://github.com/firebase/firebase-ios-sdk
   - Products: **FirebaseAuth**, **FirebaseFirestore**, **FirebaseCore**, **GoogleSignIn**

2. Add `GoogleService-Info.plist` to the StudyOS target.
   - Ensure it’s included in the app bundle (Build Phases → Copy Bundle Resources).

3. Enable Sign-In providers in Firebase Console:
   - Apple Sign-In
   - Google Sign-In
   - Email/Password (optional)

4. Configure Sign in with Apple capability:
   - Xcode → Target → Signing & Capabilities → + Capability → Sign in with Apple

5. Configure URL Types for Google Sign-In:
   - Add reversed client ID from `GoogleService-Info.plist` under URL Types.

6. Firestore Rules (starter example):
   - Allow authenticated users to read/write only their own data:
   ```
   rules_version = '2';
   service cloud.firestore {
     match /databases/{database}/documents {
       match /users/{userId}/assignments/{assignmentId} {
         allow read, write: if request.auth != null && request.auth.uid == userId;
       }
     }
   }
   ```

import { Timestamp } from "firebase-admin/firestore";
import { firestore } from "../config/firebase";
import type { UserAuthRecord } from "../types/auth";

const COLLECTION = "user_auth";

function recordRef(userId: string) {
  return firestore.collection(COLLECTION).doc(userId);
}

export async function getUserAuthRecord(userId: string): Promise<UserAuthRecord | null> {
  const snapshot = await recordRef(userId).get();
  if (!snapshot.exists) {
    return null;
  }

  const data = snapshot.data() as UserAuthRecord;
  return data;
}

export async function upsertUserAuthRecord(record: UserAuthRecord): Promise<void> {
  await recordRef(record.userId).set(
    {
      ...record,
      updatedAt: Timestamp.now().toDate().toISOString()
    },
    { merge: true }
  );
}

export async function deleteUserAuthRecord(userId: string): Promise<void> {
  await recordRef(userId).delete();
}

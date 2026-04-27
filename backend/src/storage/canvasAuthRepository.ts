import { Timestamp } from "firebase-admin/firestore";
import { firestore } from "../config/firebase";

export type CanvasAuthRecord = {
  userId: string;
  canvasDomain: string;
  canvasAccessToken: string;
  connectedAt: string;
};

const COLLECTION = "canvas_auth";

function recordRef(userId: string) {
  return firestore.collection(COLLECTION).doc(userId);
}

export async function getCanvasAuthRecord(userId: string): Promise<CanvasAuthRecord | null> {
  const snapshot = await recordRef(userId).get();
  if (!snapshot.exists) return null;
  return snapshot.data() as CanvasAuthRecord;
}

export async function upsertCanvasAuthRecord(record: CanvasAuthRecord): Promise<void> {
  await recordRef(record.userId).set(
    { ...record, updatedAt: Timestamp.now().toDate().toISOString() },
    { merge: true }
  );
}

export async function deleteCanvasAuthRecord(userId: string): Promise<void> {
  await recordRef(userId).delete();
}

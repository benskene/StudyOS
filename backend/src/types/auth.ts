export type UserAuthRecord = {
  userId: string;
  googleAccessToken: string;
  googleRefreshToken: string;
  tokenExpiry: string | null;
  connectedAt: string;
};

export type AuthenticatedUser = {
  userId: string;
  dbUserId?: string;
};

export type OAuthStatePayload = {
  userId: string;
  nonce: string;
  issuedAt: number;
};

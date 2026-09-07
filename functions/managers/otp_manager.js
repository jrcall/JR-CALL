'use strict';

// ===============================================================
// JR CALL
// File: otp_manager.js
// Location: functions/managers/otp_manager.js
//
// OTP / AUTH MASTER FILE 07 / 09
//
// EMAIL OTP MANAGER — PART 1 / 2
//
// ===============================================================
//
// CURRENT JR CALL AUTH CONTRACT:
//
// PHONE SIGNUP / LOGIN:
//
// ✓ Phone OTP is NOT generated here.
// ✓ Phone OTP is NOT verified here.
// ✓ Firebase Authentication remains the sole Phone OTP authority.
// ✓ No fake/local Phone OTP.
// ✓ No Phone password.
// ✓ No Phone OTP persistence.
//
// EMAIL LOGIN:
//
// ✓ Normal Email Login = Email + Password directly.
// ✓ Normal Email Login DOES NOT require JR CALL Email OTP.
// ✓ emailLogin purpose remains compatibility-only.
// ✓ Existing legacy callers are not broken.
//
// ACCOUNT CREATION:
//
// ✓ Phone authentication remains mandatory before account creation.
// ✓ Email is optional.
// ✓ If Email is added, Password is mandatory client-side.
// ✓ Email/Password must link to the SAME Phone-authenticated UID.
// ✓ Standalone Email account creation is not owned here.
//
// EMAIL OTP:
//
// ✓ emailSignUp compatibility flow preserved.
// ✓ emailChange compatibility flow preserved.
// ✓ emailLogin compatibility flow preserved but normal Login does
//   NOT call it.
// ✓ Password Recovery is NOT owned by this file.
//
// PASSWORD RECOVERY:
//
// ✓ Owned by otp_manager_part2.js.
// ✓ Recovery OTP remains available.
// ✓ Raw recovery Password is never handled here.
//
// SECURITY:
//
// ✓ Firebase UID remains canonical identity.
// ✓ Raw OTP is never persisted.
// ✓ OTP stored only as HMAC-SHA256 hash.
// ✓ 6-digit cryptographically secure OTP.
// ✓ 5-minute expiration.
// ✓ 60-second resend cooldown.
// ✓ 15-minute rate window.
// ✓ Maximum 5 sends/window.
// ✓ IP-bound rate-limit dimension.
// ✓ Challenge IDs are random UUIDs.
// ✓ Resend delivery uses one idempotency key per challenge.
//
// EXPORT:
//
// ✓ sendEmailOtpHandler only.
//
// PROTECTED:
//
// ✓ Call Engine untouched.
// ✓ Message Engine untouched.
// ✓ WebRTC untouched.
// ✓ Signaling untouched.
// ===============================================================

const crypto = require('crypto');

const {
  getAuth,
} = require('firebase-admin/auth');

const {
  getFirestore,
  FieldValue,
  Timestamp,
} = require('firebase-admin/firestore');

const {
  HttpsError,
} = require('firebase-functions/v2/https');

const {
  defineSecret,
  defineString,
} = require('firebase-functions/params');

// ===============================================================
// FIRESTORE
// ===============================================================

const db = getFirestore();

// ===============================================================
// COLLECTIONS
// ===============================================================

const USERS_COLLECTION =
  'users';

const EMAIL_OTP_COLLECTION =
  'email_otp_challenges';

const EMAIL_OTP_RATE_COLLECTION =
  'email_otp_rate_limits';

// ===============================================================
// SECRETS / PARAMETERS
// ===============================================================

const RESEND_API_KEY =
  defineSecret('RESEND_API_KEY');

const EMAIL_OTP_HASH_SECRET =
  defineSecret('EMAIL_OTP_HASH_SECRET');

const EMAIL_OTP_FROM =
  defineString(
    'EMAIL_OTP_FROM',
    {
      default: '',
    },
  );

// ===============================================================
// OTP POLICY
// ===============================================================

const OTP_LENGTH =
  6;

const OTP_EXPIRY_SECONDS =
  5 * 60;

const OTP_RESEND_COOLDOWN_SECONDS =
  60;

const OTP_RATE_WINDOW_SECONDS =
  15 * 60;

const OTP_MAX_SENDS_PER_WINDOW =
  5;

const OTP_MAX_VERIFY_ATTEMPTS =
  5;

// ===============================================================
// EMAIL OTP PURPOSES
//
// IMPORTANT:
//
// emailLogin remains only for compatibility.
// Normal JR CALL Email Login is direct Email + Password.
// ===============================================================

const EMAIL_SIGNUP_PURPOSE =
  'emailSignUp';

const EMAIL_LOGIN_PURPOSE =
  'emailLogin';

const EMAIL_CHANGE_PURPOSE =
  'emailChange';

const AUTHENTICATED_EMAIL_PURPOSES =
  new Set([
    EMAIL_SIGNUP_PURPOSE,
    EMAIL_CHANGE_PURPOSE,
  ]);

const ALL_STANDARD_EMAIL_PURPOSES =
  new Set([
    EMAIL_SIGNUP_PURPOSE,
    EMAIL_LOGIN_PURPOSE,
    EMAIL_CHANGE_PURPOSE,
  ]);

// ===============================================================
// STRING NORMALIZATION
// ===============================================================

function cleanString(value) {
  return typeof value === 'string'
    ? value.trim()
    : '';
}

function normalizeEmail(value) {
  return cleanString(
    value,
  ).toLowerCase();
}

function normalizePurpose(value) {
  return cleanString(
    value,
  );
}

// ===============================================================
// EMAIL VALIDATION
// ===============================================================

function isValidEmail(value) {
  return (
    typeof value === 'string' &&
    value.length > 3 &&
    value.length <= 254 &&
    /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(
      value,
    )
  );
}

// ===============================================================
// TIMESTAMP HELPERS
// ===============================================================

function isTimestamp(value) {
  return value instanceof Timestamp;
}

function timestampToMillis(value) {
  return isTimestamp(value)
    ? value.toMillis()
    : 0;
}

function secondsFromNow(seconds) {
  return Timestamp.fromMillis(
    Date.now() +
      seconds * 1000,
  );
}

// ===============================================================
// HASH / RANDOM
// ===============================================================

function sha256(value) {
  return crypto
    .createHash(
      'sha256',
    )
    .update(
      String(value),
    )
    .digest(
      'hex',
    );
}

function createChallengeId() {
  return crypto.randomUUID();
}

function createSixDigitOtp() {
  return crypto
    .randomInt(
      0,
      1000000,
    )
    .toString()
    .padStart(
      OTP_LENGTH,
      '0',
    );
}

// ===============================================================
// OTP HASH
//
// Raw OTP is never stored.
//
// Hash input binds OTP to:
//
// challengeId + Firebase UID + Email + purpose
//
// Therefore one OTP cannot be safely reused for another challenge.
// ===============================================================

function createOtpHash({
  challengeId,
  uid,
  email,
  purpose,
  otp,
  secret,
}) {
  const payload =
    [
      challengeId,
      uid,
      email,
      purpose,
      otp,
    ].join('|');

  return crypto
    .createHmac(
      'sha256',
      secret,
    )
    .update(
      payload,
    )
    .digest(
      'hex',
    );
}

// ===============================================================
// CALLABLE DATA
// ===============================================================

function callableData(request) {
  if (
    request &&
    request.data &&
    typeof request.data === 'object' &&
    !Array.isArray(
      request.data,
    )
  ) {
    return request.data;
  }

  return {};
}

// ===============================================================
// CALLABLE UID
// ===============================================================

function optionalCallableUid(request) {
  const uid =
    request?.auth?.uid;

  return typeof uid === 'string'
    ? uid.trim()
    : '';
}

function requireCallableUid(request) {
  const uid =
    optionalCallableUid(
      request,
    );

  if (uid === '') {
    throw new HttpsError(
      'unauthenticated',
      'Firebase Authentication is required.',
    );
  }

  return uid;
}

// ===============================================================
// CLIENT IP
// ===============================================================

function resolveClientIp(request) {
  const rawRequest =
    request?.rawRequest;

  if (!rawRequest) {
    return 'unknown';
  }

  const forwarded =
    typeof rawRequest.headers?.[
      'x-forwarded-for'
    ] === 'string'
      ? rawRequest.headers[
          'x-forwarded-for'
        ]
      : '';

  if (forwarded !== '') {
    return forwarded
      .split(',')[0]
      .trim()
      .substring(
        0,
        128,
      );
  }

  const requestIp =
    typeof rawRequest.ip === 'string'
      ? rawRequest.ip.trim()
      : '';

  return requestIp === ''
    ? 'unknown'
    : requestIp.substring(
        0,
        128,
      );
}

function resolveIpHash(request) {
  return sha256(
    resolveClientIp(
      request,
    ),
  );
}

// ===============================================================
// EMAIL BACKEND CONFIGURATION
//
// Secrets are read only while the bound Cloud Function executes.
//
// index.js MUST bind:
//
// RESEND_API_KEY
// EMAIL_OTP_HASH_SECRET
//
// to sendEmailOtp.
// ===============================================================

function requireEmailBackendConfiguration() {
  const resendApiKey =
    RESEND_API_KEY
      .value()
      .trim();

  const hashSecret =
    EMAIL_OTP_HASH_SECRET
      .value()
      .trim();

  const emailFrom =
    EMAIL_OTP_FROM
      .value()
      .trim();

  if (
    resendApiKey === '' ||
    hashSecret === '' ||
    emailFrom === ''
  ) {
    console.error(
      'JR CALL Email OTP configuration is incomplete.',
    );

    throw new HttpsError(
      'failed-precondition',
      'Email OTP service is not completely configured.',
    );
  }

  return {
    resendApiKey,
    hashSecret,
    emailFrom,
  };
}

// ===============================================================
// FIREBASE PROVIDER HELPERS
// ===============================================================

function providerIdsOf(firebaseUser) {
  const providers =
    Array.isArray(
      firebaseUser?.providerData,
    )
      ? firebaseUser.providerData
      : [];

  return new Set(
    providers
      .map(
        (provider) =>
          cleanString(
            provider?.providerId,
          ),
      )
      .filter(
        (providerId) =>
          providerId !== '',
      ),
  );
}

function hasPasswordProvider(firebaseUser) {
  return providerIdsOf(
    firebaseUser,
  ).has(
    'password',
  );
}

function hasPhoneProvider(firebaseUser) {
  return providerIdsOf(
    firebaseUser,
  ).has(
    'phone',
  );
}

// ===============================================================
// USABLE JR CALL PROFILE
// ===============================================================

async function getUsableExistingProfile(
  uid,
) {
  const cleanUid =
    cleanString(
      uid,
    );

  if (cleanUid === '') {
    return null;
  }

  const snapshot =
    await db
      .collection(
        USERS_COLLECTION,
      )
      .doc(
        cleanUid,
      )
      .get();

  if (!snapshot.exists) {
    return null;
  }

  const profile =
    snapshot.data() ||
    {};

  if (
    profile.isDeleted === true ||
    profile.isBlocked === true
  ) {
    return null;
  }

  return profile;
}

// ===============================================================
// EMAIL UNIQUENESS
//
// The requested Email may:
//
// ✓ not exist in Firebase Auth, or
// ✓ already belong to this SAME Firebase UID.
//
// It must never belong to a different Firebase UID.
// ===============================================================

async function ensureEmailAvailableForUid(
  email,
  uid,
) {
  try {
    const existingUser =
      await getAuth()
        .getUserByEmail(
          email,
        );

    if (
      cleanString(
        existingUser.uid,
      ) !== uid
    ) {
      throw new HttpsError(
        'already-exists',
        'This Email is already linked to another account.',
      );
    }
  } catch (error) {
    if (
      error instanceof HttpsError
    ) {
      throw error;
    }

    if (
      error?.code ===
      'auth/user-not-found'
    ) {
      return;
    }

    console.error(
      'JR CALL Email uniqueness lookup failed:',
      error,
    );

    throw new HttpsError(
      'unavailable',
      'Email availability could not be verified right now.',
    );
  }
}

// ===============================================================
// AUTHENTICATED EMAIL TARGET
//
// Used by compatibility Email Signup / Email Change OTP.
//
// IMPORTANT:
//
// JR CALL account identity remains the existing Firebase UID.
//
// For Email Signup compatibility, the current account must already
// have a verified Firebase Phone identity. This prevents an
// Email-only account from using this path as account creation.
// ===============================================================

async function resolveAuthenticatedEmailTarget({
  uid,
  requestedEmail,
  purpose,
}) {
  let firebaseUser;

  try {
    firebaseUser =
      await getAuth()
        .getUser(
          uid,
        );
  } catch (error) {
    console.error(
      'JR CALL authenticated Firebase user lookup failed:',
      error,
    );

    throw new HttpsError(
      'unauthenticated',
      'The authenticated Firebase account could not be verified.',
    );
  }

  if (
    firebaseUser.disabled === true
  ) {
    throw new HttpsError(
      'permission-denied',
      'This account is unavailable.',
    );
  }

  const firebaseUid =
    cleanString(
      firebaseUser.uid,
    );

  if (
    firebaseUid === '' ||
    firebaseUid !== uid
  ) {
    throw new HttpsError(
      'unauthenticated',
      'The authenticated Firebase account is invalid.',
    );
  }

  const currentEmail =
    normalizeEmail(
      firebaseUser.email,
    );

  const firebasePhone =
    cleanString(
      firebaseUser.phoneNumber,
    );

  // -------------------------------------------------------------
  // EMAIL SIGNUP COMPATIBILITY
  //
  // Phone-authenticated Firebase account is mandatory.
  // -------------------------------------------------------------

  if (
    purpose ===
    EMAIL_SIGNUP_PURPOSE
  ) {
    if (
      firebasePhone === '' ||
      !hasPhoneProvider(
        firebaseUser,
      )
    ) {
      throw new HttpsError(
        'failed-precondition',
        'A Firebase-verified Phone Number is required before adding Email.',
      );
    }

    if (
      currentEmail !== '' &&
      currentEmail !== requestedEmail
    ) {
      throw new HttpsError(
        'failed-precondition',
        'A different Email is already linked to this account.',
      );
    }

    await ensureEmailAvailableForUid(
      requestedEmail,
      uid,
    );

    return {
      uid,
      email:
        requestedEmail,
      firebaseUser,
    };
  }

  // -------------------------------------------------------------
  // EMAIL CHANGE
  // -------------------------------------------------------------

  if (
    purpose ===
    EMAIL_CHANGE_PURPOSE
  ) {
    if (
      currentEmail !== '' &&
      currentEmail === requestedEmail
    ) {
      throw new HttpsError(
        'failed-precondition',
        'The new Email must be different from the current Email.',
      );
    }

    await ensureEmailAvailableForUid(
      requestedEmail,
      uid,
    );

    return {
      uid,
      email:
        requestedEmail,
      firebaseUser,
    };
  }

  throw new HttpsError(
    'invalid-argument',
    'Unsupported authenticated Email OTP purpose.',
  );
}

// ===============================================================
// EMAIL LOGIN TARGET — COMPATIBILITY ONLY
//
// IMPORTANT:
//
// Normal JR CALL Email Login is now:
//
// Email + Password
//      ↓
// Firebase Authentication
//      ↓
// direct Login
//
// Therefore current LoginScreen must NOT call this backend path.
//
// This compatibility path is intentionally preserved so older
// clients / transitional deployments do not crash.
//
// Enumeration resistance remains preserved.
// ===============================================================

async function resolveEmailLoginTarget(
  email,
) {
  let firebaseUser;

  try {
    firebaseUser =
      await getAuth()
        .getUserByEmail(
          email,
        );
  } catch (error) {
    if (
      error?.code ===
      'auth/user-not-found'
    ) {
      return null;
    }

    console.error(
      'JR CALL Email Login compatibility lookup failed:',
      error,
    );

    throw new HttpsError(
      'unavailable',
      'Email verification is temporarily unavailable.',
    );
  }

  if (
    firebaseUser.disabled === true ||
    !hasPasswordProvider(
      firebaseUser,
    )
  ) {
    return null;
  }

  const firebaseUid =
    cleanString(
      firebaseUser.uid,
    );

  if (firebaseUid === '') {
    return null;
  }

  const firebaseEmail =
    normalizeEmail(
      firebaseUser.email,
    );

  if (
    firebaseEmail === '' ||
    firebaseEmail !== email
  ) {
    return null;
  }

  const profile =
    await getUsableExistingProfile(
      firebaseUid,
    );

  if (!profile) {
    return null;
  }

  const profileEmail =
    normalizeEmail(
      profile.emailNormalized ||
      profile.email ||
      '',
    );

  if (
    profileEmail !== '' &&
    profileEmail !== firebaseEmail
  ) {
    console.error(
      'JR CALL Email compatibility profile/Auth mismatch.',
      {
        uid:
          firebaseUid,
      },
    );

    return null;
  }

  return {
    uid:
      firebaseUid,
    email:
      firebaseEmail,
    firebaseUser,
    profile,
  };
}

// ===============================================================
// ENUMERATION-RESISTANT ACCEPTED RESPONSE
//
// Used for compatibility Email Login.
//
// No real challenge is persisted for unknown accounts.
// ===============================================================

function createDecoyAcceptedResponse() {
  return {
    success:
      true,

    challengeId:
      createChallengeId(),

    expiresIn:
      OTP_EXPIRY_SECONDS,

    resendAfter:
      OTP_RESEND_COOLDOWN_SECONDS,
  };
}

// ===============================================================
// RATE DOCUMENT ID
// ===============================================================

function buildOtpRateDocumentId({
  namespace,
  uid,
  email,
  purpose,
  ipHash,
}) {
  return sha256(
    [
      namespace,
      uid,
      purpose,
      email,
      ipHash || '',
    ].join('|'),
  );
}

// ===============================================================
// RESERVE OTP CHALLENGE
//
// OTP HASH ONLY is persisted.
// Raw OTP is NOT persisted.
// ===============================================================

async function reserveOtpChallenge({
  uid,
  email,
  purpose,
  challengeId,
  otpHash,
  rateCollection,
  rateNamespace,
  ipHash = '',
}) {
  const now =
    Timestamp.now();

  const expiresAt =
    secondsFromNow(
      OTP_EXPIRY_SECONDS,
    );

  const challengeRef =
    db
      .collection(
        EMAIL_OTP_COLLECTION,
      )
      .doc(
        challengeId,
      );

  const rateDocumentId =
    buildOtpRateDocumentId({
      namespace:
        rateNamespace,
      uid,
      email,
      purpose,
      ipHash,
    });

  const rateRef =
    db
      .collection(
        rateCollection,
      )
      .doc(
        rateDocumentId,
      );

  await db.runTransaction(
    async (transaction) => {
      const rateSnapshot =
        await transaction.get(
          rateRef,
        );

      let sendCount =
        0;

      let windowStartedAt =
        now;

      let lastSentAt =
        null;

      if (
        rateSnapshot.exists
      ) {
        const rateData =
          rateSnapshot.data() ||
          {};

        const storedCount =
          Number.isInteger(
            rateData.sendCount,
          )
            ? Math.max(
                rateData.sendCount,
                0,
              )
            : 0;

        const windowStartMillis =
          timestampToMillis(
            rateData.windowStartedAt,
          );

        const windowExpired =
          windowStartMillis === 0 ||
          now.toMillis() -
              windowStartMillis >=
            OTP_RATE_WINDOW_SECONDS *
              1000;

        if (!windowExpired) {
          sendCount =
            storedCount;

          if (
            isTimestamp(
              rateData.windowStartedAt,
            )
          ) {
            windowStartedAt =
              rateData.windowStartedAt;
          }
        }

        if (
          !windowExpired &&
          isTimestamp(
            rateData.lastSentAt,
          )
        ) {
          lastSentAt =
            rateData.lastSentAt;
        }
      }

      // ---------------------------------------------------------
      // RESEND COOLDOWN
      // ---------------------------------------------------------

      if (
        lastSentAt !== null
      ) {
        const elapsedMillis =
          now.toMillis() -
          lastSentAt.toMillis();

        const cooldownMillis =
          OTP_RESEND_COOLDOWN_SECONDS *
          1000;

        if (
          elapsedMillis <
          cooldownMillis
        ) {
          const retryAfterSeconds =
            Math.ceil(
              (
                cooldownMillis -
                elapsedMillis
              ) /
              1000,
            );

          throw new HttpsError(
            'resource-exhausted',
            'Please wait before requesting another Email OTP.',
            {
              retryAfterSeconds,
            },
          );
        }
      }

      // ---------------------------------------------------------
      // SEND WINDOW
      // ---------------------------------------------------------

      if (
        sendCount >=
        OTP_MAX_SENDS_PER_WINDOW
      ) {
        throw new HttpsError(
          'resource-exhausted',
          'Too many Email OTP requests. Please try again later.',
        );
      }

      // ---------------------------------------------------------
      // CHALLENGE
      // ---------------------------------------------------------

      transaction.create(
        challengeRef,
        {
          challengeId,

          uid,

          email,

          emailHash:
            sha256(
              email,
            ),

          purpose,

          otpHash,

          attempts:
            0,

          maxAttempts:
            OTP_MAX_VERIFY_ATTEMPTS,

          used:
            false,

          verificationStatus:
            'pending',

          deliveryStatus:
            'pending',

          createdAt:
            now,

          expiresAt,

          verifiedAt:
            null,

          usedAt:
            null,

          expiredAt:
            null,

          lockedAt:
            null,

          lastFailedAttemptAt:
            null,

          finalizationLeaseId:
            null,

          finalizationLeaseExpiresAt:
            null,

          deliveryMessageId:
            null,

          deliveredAt:
            null,

          failedAt:
            null,

          ipHash:
            ipHash || null,
        },
      );

      // ---------------------------------------------------------
      // RATE LIMIT
      // ---------------------------------------------------------

      transaction.set(
        rateRef,
        {
          uidHash:
            sha256(
              uid,
            ),

          emailHash:
            sha256(
              email,
            ),

          purpose,

          ipHash:
            ipHash || null,

          sendCount:
            sendCount + 1,

          windowStartedAt,

          lastSentAt:
            now,

          updatedAt:
            now,
        },
        {
          merge:
            true,
        },
      );
    },
  );

  return {
    challengeRef,
    expiresAt,
  };
}

// ===============================================================
// PURPOSE LABEL
// ===============================================================

function otpPurposeLabel(
  purpose,
) {
  switch (purpose) {
    case EMAIL_SIGNUP_PURPOSE:
      return 'account verification';

    case EMAIL_CHANGE_PURPOSE:
      return 'email change verification';

    case EMAIL_LOGIN_PURPOSE:
      return 'login verification';

    default:
      return 'verification';
  }
}

// ===============================================================
// EMAIL SUBJECT
// ===============================================================

function otpEmailSubject(
  purpose,
) {
  switch (purpose) {
    case EMAIL_SIGNUP_PURPOSE:
      return 'Your JR CALL account verification code';

    case EMAIL_CHANGE_PURPOSE:
      return 'Your JR CALL email change code';

    case EMAIL_LOGIN_PURPOSE:
      return 'Your JR CALL verification code';

    default:
      return 'Your JR CALL verification code';
  }
}

// ===============================================================
// SEND EMAIL THROUGH RESEND
// ===============================================================

async function sendOtpEmail({
  apiKey,
  from,
  email,
  otp,
  purpose,
  challengeId,
}) {
  const purposeLabel =
    otpPurposeLabel(
      purpose,
    );

  const subject =
    otpEmailSubject(
      purpose,
    );

  const text =
    [
      'JR CALL',
      '',
      `Your ${purposeLabel} code is ${otp}.`,
      '',
      'This code expires in 5 minutes.',
      '',
      'Never share this code with anyone.',
      '',
      'If you did not request this code, you can safely ignore this email.',
    ].join('\n');

  const html = `
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width">
<title>JR CALL Verification</title>
</head>

<body style="
  margin:0;
  padding:0;
  background:#F6F8FC;
  font-family:Arial,Helvetica,sans-serif;
  color:#111827;
">
  <div style="
    max-width:560px;
    margin:0 auto;
    padding:32px 18px;
  ">
    <div style="
      background:#FFFFFF;
      border:1px solid #E3E8F1;
      border-radius:24px;
      padding:32px 24px;
    ">
      <div style="
        font-size:26px;
        font-weight:800;
        text-align:center;
      ">
        JR CALL
      </div>

      <div style="
        margin-top:8px;
        text-align:center;
        color:#68758C;
        font-size:14px;
      ">
        Secure Verification
      </div>

      <div style="
        margin-top:30px;
        text-align:center;
        color:#374151;
        font-size:15px;
      ">
        Your ${purposeLabel} code is:
      </div>

      <div style="
        margin:22px auto;
        padding:20px 16px;
        border-radius:18px;
        background:#EFF6FF;
        color:#1769F5;
        font-size:34px;
        font-weight:800;
        letter-spacing:9px;
        text-align:center;
      ">
        ${otp}
      </div>

      <div style="
        text-align:center;
        color:#68758C;
        font-size:14px;
      ">
        This code expires in <strong>5 minutes</strong>.
      </div>

      <div style="
        margin-top:14px;
        text-align:center;
        color:#68758C;
        font-size:13px;
      ">
        Never share this verification code with anyone.
      </div>

      <div style="
        margin-top:24px;
        padding-top:20px;
        border-top:1px solid #EEF1F5;
        text-align:center;
        color:#8A94A6;
        font-size:12px;
      ">
        If you did not request this code, you can safely ignore this email.
      </div>
    </div>
  </div>
</body>
</html>
`;

  const response =
    await fetch(
      'https://api.resend.com/emails',
      {
        method:
          'POST',

        headers: {
          Authorization:
            `Bearer ${apiKey}`,

          'Content-Type':
            'application/json',

          'User-Agent':
            'JR-CALL-Firebase-Functions/3.0',

          'Idempotency-Key':
            `jr-call-otp/${challengeId}`,
        },

        body:
          JSON.stringify({
            from,

            to: [
              email,
            ],

            subject,

            text,

            html,
          }),
      },
    );

  let responseData =
    null;

  try {
    responseData =
      await response.json();
  } catch (_) {
    responseData =
      null;
  }

  if (!response.ok) {
    console.error(
      'JR CALL Email provider rejected request:',
      {
        status:
          response.status,

        providerCode:
          responseData?.name ||
          responseData?.code ||
          null,
      },
    );

    throw new Error(
      'EMAIL_DELIVERY_FAILED',
    );
  }

  const messageId =
    typeof responseData?.id ===
      'string'
      ? responseData.id.trim()
      : '';

  return {
    messageId:
      messageId === ''
        ? null
        : messageId,
  };
}

// ===============================================================
// MARK DELIVERY SUCCESS
// ===============================================================

async function markOtpDelivered({
  challengeRef,
  messageId,
}) {
  await challengeRef.update({
    deliveryStatus:
      'sent',

    deliveryMessageId:
      messageId,

    deliveredAt:
      FieldValue.serverTimestamp(),

    failedAt:
      null,
  });
}

// ===============================================================
// MARK DELIVERY FAILURE
// ===============================================================

async function markOtpDeliveryFailed({
  challengeRef,
}) {
  try {
    await challengeRef.update({
      deliveryStatus:
        'failed',

      verificationStatus:
        'delivery_failed',

      failedAt:
        FieldValue.serverTimestamp(),

      finalizationLeaseId:
        null,

      finalizationLeaseExpiresAt:
        null,
    });
  } catch (error) {
    console.error(
      'JR CALL failed to mark Email OTP delivery failure:',
      error,
    );
  }
}

// ===============================================================
// CREATE + DELIVER OTP
// ===============================================================

async function createAndDeliverOtp({
  request,
  uid,
  email,
  purpose,
  rateCollection,
  rateNamespace,
  resendApiKey,
  hashSecret,
  emailFrom,
}) {
  const cleanUid =
    cleanString(
      uid,
    );

  const normalizedEmail =
    normalizeEmail(
      email,
    );

  if (
    cleanUid === '' ||
    !isValidEmail(
      normalizedEmail,
    )
  ) {
    throw new HttpsError(
      'failed-precondition',
      'The Email verification target is invalid.',
    );
  }

  const challengeId =
    createChallengeId();

  const otp =
    createSixDigitOtp();

  const otpHash =
    createOtpHash({
      challengeId,

      uid:
        cleanUid,

      email:
        normalizedEmail,

      purpose,

      otp,

      secret:
        hashSecret,
    });

  const reservation =
    await reserveOtpChallenge({
      uid:
        cleanUid,

      email:
        normalizedEmail,

      purpose,

      challengeId,

      otpHash,

      rateCollection,

      rateNamespace,

      ipHash:
        resolveIpHash(
          request,
        ),
    });

  try {
    const delivery =
      await sendOtpEmail({
        apiKey:
          resendApiKey,

        from:
          emailFrom,

        email:
          normalizedEmail,

        otp,

        purpose,

        challengeId,
      });

    await markOtpDelivered({
      challengeRef:
        reservation.challengeRef,

      messageId:
        delivery.messageId,
    });
  } catch (error) {
    await markOtpDeliveryFailed({
      challengeRef:
        reservation.challengeRef,
    });

    console.error(
      'JR CALL Email OTP delivery failed:',
      error,
    );

    throw new HttpsError(
      'unavailable',
      'Email OTP could not be delivered. Please try again.',
    );
  }

  return {
    success:
      true,

    challengeId,

    expiresIn:
      OTP_EXPIRY_SECONDS,

    resendAfter:
      OTP_RESEND_COOLDOWN_SECONDS,
  };
}

// ===============================================================
// SEND EMAIL OTP HANDLER
//
// CURRENT ACTIVE OWNERSHIP:
//
// emailSignUp:
//   compatibility Email verification after Firebase Phone auth.
//
// emailChange:
//   authenticated Email-change verification.
//
// emailLogin:
//   compatibility-only.
//   Normal Email + Password Login does NOT call this.
//
// Password Recovery:
//   NOT owned here.
//   otp_manager_part2.js owns recovery.
// ===============================================================

async function sendEmailOtpHandler(
  request,
) {
  const data =
    callableData(
      request,
    );

  const requestedEmail =
    normalizeEmail(
      data.email,
    );

  const purpose =
    normalizePurpose(
      data.purpose,
    );

  // -------------------------------------------------------------
  // INPUT VALIDATION
  // -------------------------------------------------------------

  if (
    !isValidEmail(
      requestedEmail,
    )
  ) {
    throw new HttpsError(
      'invalid-argument',
      'A valid Email address is required.',
    );
  }

  if (
    !ALL_STANDARD_EMAIL_PURPOSES.has(
      purpose,
    )
  ) {
    throw new HttpsError(
      'invalid-argument',
      'Unsupported Email OTP purpose.',
    );
  }

  const {
    resendApiKey,
    hashSecret,
    emailFrom,
  } =
    requireEmailBackendConfiguration();

  // -------------------------------------------------------------
  // EMAIL LOGIN — COMPATIBILITY ONLY
  //
  // Current LoginScreen must perform:
  //
  // AuthService.signInWithEmailPassword()
  //
  // and MUST NOT depend on this branch.
  // -------------------------------------------------------------

  if (
    purpose ===
    EMAIL_LOGIN_PURPOSE
  ) {
    const target =
      await resolveEmailLoginTarget(
        requestedEmail,
      );

    if (!target) {
      return createDecoyAcceptedResponse();
    }

    return createAndDeliverOtp({
      request,

      uid:
        target.uid,

      email:
        target.email,

      purpose,

      rateCollection:
        EMAIL_OTP_RATE_COLLECTION,

      rateNamespace:
        'legacy-email-login',

      resendApiKey,

      hashSecret,

      emailFrom,
    });
  }

  // -------------------------------------------------------------
  // AUTHENTICATED EMAIL SIGNUP / CHANGE
  // -------------------------------------------------------------

  if (
    AUTHENTICATED_EMAIL_PURPOSES.has(
      purpose,
    )
  ) {
    const uid =
      requireCallableUid(
        request,
      );

    const target =
      await resolveAuthenticatedEmailTarget({
        uid,

        requestedEmail,

        purpose,
      });

    return createAndDeliverOtp({
      request,

      uid:
        target.uid,

      email:
        target.email,

      purpose,

      rateCollection:
        EMAIL_OTP_RATE_COLLECTION,

      rateNamespace:
        'authenticated-email-otp',

      resendApiKey,

      hashSecret,

      emailFrom,
    });
  }

  throw new HttpsError(
    'invalid-argument',
    'Unsupported Email OTP purpose.',
  );
}

// ===============================================================
// EXPORTS — PART 1
// ===============================================================

module.exports = {
  sendEmailOtpHandler,
};

// ===============================================================
// END OF FILE
//
// OTP / AUTH MASTER FILE 07 / 09
//
// FINAL CONTRACT:
//
// PHONE:
//
// ✓ No Phone OTP generated here.
// ✓ No Phone OTP verified here.
// ✓ No Phone SMS provider here.
// ✓ No Phone password.
// ✓ Firebase Authentication remains sole Phone OTP authority.
//
// EMAIL LOGIN:
//
// ✓ Normal Email + Password Login is direct.
// ✓ Normal Email Login does not depend on this file.
// ✓ Legacy emailLogin OTP API preserved only for compatibility.
//
// ACCOUNT CREATION:
//
// ✓ Phone-authenticated Firebase UID remains canonical.
// ✓ Email signup compatibility cannot create Email-only identity.
// ✓ Email uniqueness protected.
// ✓ Email/Password ownership remains client/AuthService linking.
//
// EMAIL OTP:
//
// ✓ Email signup compatibility preserved.
// ✓ Email change preserved.
// ✓ Cryptographically secure 6-digit OTP.
// ✓ HMAC-SHA256 hash only.
// ✓ Raw OTP never persisted.
// ✓ 5-minute expiry.
// ✓ 60-second resend cooldown.
// ✓ Maximum 5 sends / 15-minute window.
// ✓ IP-aware rate limiting.
// ✓ Delivery state persisted.
// ✓ Resend idempotency preserved.
//
// PASSWORD RECOVERY:
//
// ✓ Not duplicated here.
// ✓ Remains owned by otp_manager_part2.js.
//
// SECURITY:
//
// ✓ Firebase UID canonical.
// ✓ Secret values remain server-side.
// ✓ No fake/local OTP.
// ✓ No App Verification bypass.
// ✓ No reCAPTCHA bypass.
// ✓ No Play Integrity bypass.
//
// PROTECTED:
//
// ✓ Call Engine untouched.
// ✓ Message Engine untouched.
// ✓ WebRTC untouched.
// ✓ Signaling untouched.
//
// SAVE / REPLACE:
//
// functions/managers/otp_manager.js
//
// NEXT:
//
// functions/managers/otp_manager_part2.js
//
// THEN:
//
// functions/index.js
// ===============================================================
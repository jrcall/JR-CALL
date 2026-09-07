'use strict';

// ===============================================================
// JR CALL
// File: otp_manager_part2.js
// Location: functions/managers/otp_manager_part2.js
//
// OTP / AUTH MASTER FILE 08 / 09
//
// EMAIL OTP / PASSWORD RECOVERY MANAGER
// PART 2 / 2
//
// ===============================================================
//
// CURRENT JR CALL AUTH CONTRACT:
//
// PHONE:
//
// ✓ Phone Signup requires Firebase Phone verification.
// ✓ Phone Login requires Firebase Phone verification.
// ✓ Phone OTP is NOT generated here.
// ✓ Phone OTP is NOT verified here.
// ✓ No Phone password.
// ✓ No fake/local Phone OTP.
// ✓ No Phone OTP persistence.
// ✓ Firebase Authentication remains Phone OTP authority.
//
// EMAIL LOGIN:
//
// ✓ Normal Email Login = Email + Password directly.
// ✓ Normal Email Login DOES NOT require Email OTP.
// ✓ emailLogin OTP verification remains compatibility-only.
// ✓ Existing transitional/legacy clients are not broken.
//
// ACCOUNT CREATION:
//
// ✓ Phone remains mandatory account identity.
// ✓ Email is optional.
// ✓ Password is required when Email/Password is linked.
// ✓ Email/Password must remain on SAME Phone Firebase UID.
// ✓ This file does NOT create standalone Email accounts.
//
// EMAIL OTP:
//
// ✓ Legacy/compatibility Email Signup OTP verification preserved.
// ✓ Legacy/compatibility Email Login OTP verification preserved.
// ✓ Email Change OTP verification preserved.
// ✓ Firebase UID remains canonical.
//
// PASSWORD RECOVERY:
//
// ✓ Recovery Email OTP send preserved.
// ✓ Recovery Email OTP verify preserved.
// ✓ Password reset through Firebase Admin.
// ✓ Refresh tokens revoked after successful password reset.
// ✓ Raw password remains request-memory-only.
//
// SECURITY:
//
// ✓ Raw OTP is NEVER persisted.
// ✓ OTP is HMAC-SHA256 hashed.
// ✓ Timing-safe hash comparison.
// ✓ Six-digit OTP.
// ✓ Five-minute expiry.
// ✓ Sixty-second resend cooldown.
// ✓ Five sends / fifteen-minute rate window.
// ✓ Five verification attempts.
// ✓ Single-use OTP.
// ✓ Finalization lease.
// ✓ Failed-attempt writes commit before callable error.
// ✓ Expiry/lock state writes commit before callable error.
// ✓ Enumeration-resistant Password Recovery.
//
// EXPORTS:
//
// ✓ verifyEmailOtpHandler
// ✓ sendPasswordRecoveryOtpHandler
// ✓ verifyPasswordRecoveryOtpHandler
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

const PASSWORD_RECOVERY_RATE_COLLECTION =
  'password_recovery_rate_limits';

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

const OTP_FINALIZATION_LEASE_SECONDS =
  60;

// ===============================================================
// PURPOSES
//
// IMPORTANT:
//
// emailLogin is compatibility-only.
// Current normal JR CALL Email Login is direct Email + Password.
// ===============================================================

const EMAIL_SIGNUP_PURPOSE =
  'emailSignUp';

const EMAIL_LOGIN_PURPOSE =
  'emailLogin';

const EMAIL_CHANGE_PURPOSE =
  'emailChange';

const PASSWORD_RECOVERY_PURPOSE =
  'passwordRecovery';

const STANDARD_EMAIL_PURPOSES =
  new Set([
    EMAIL_SIGNUP_PURPOSE,
    EMAIL_LOGIN_PURPOSE,
    EMAIL_CHANGE_PURPOSE,
  ]);

// ===============================================================
// NORMALIZATION
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

function normalizeChallengeId(value) {
  return cleanString(
    value,
  );
}

function normalizeOtp(value) {
  if (
    typeof value !== 'string' &&
    typeof value !== 'number'
  ) {
    return '';
  }

  return String(value)
    .trim()
    .replace(
      /\s+/g,
      '',
    );
}

// ===============================================================
// VALIDATION
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

function isValidOtp(value) {
  return /^\d{6}$/.test(
    value,
  );
}

function isValidPassword(value) {
  return (
    typeof value === 'string' &&
    value.length >= 6 &&
    value.length <= 4096
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
// CALLABLE AUTH
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
// TIMESTAMP
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

function createLeaseId() {
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
// challengeId + UID + Email + purpose + OTP
// are bound together by HMAC-SHA256.
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
// TIMING-SAFE HASH COMPARISON
// ===============================================================

function timingSafeHashEquals(
  storedHash,
  suppliedHash,
) {
  if (
    typeof storedHash !== 'string' ||
    typeof suppliedHash !== 'string' ||
    !/^[a-f0-9]{64}$/i.test(
      storedHash,
    ) ||
    !/^[a-f0-9]{64}$/i.test(
      suppliedHash,
    )
  ) {
    return false;
  }

  const stored =
    Buffer.from(
      storedHash,
      'hex',
    );

  const supplied =
    Buffer.from(
      suppliedHash,
      'hex',
    );

  if (
    stored.length === 0 ||
    stored.length !==
      supplied.length
  ) {
    return false;
  }

  return crypto.timingSafeEqual(
    stored,
    supplied,
  );
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

function requireOtpHashSecret() {
  const hashSecret =
    EMAIL_OTP_HASH_SECRET
      .value()
      .trim();

  if (hashSecret === '') {
    throw new HttpsError(
      'failed-precondition',
      'OTP verification service is not configured.',
    );
  }

  return hashSecret;
}

// ===============================================================
// PROVIDER HELPERS
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
// PROFILE CHECK
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
// PASSWORD RECOVERY TARGET
//
// Enumeration-resistant.
//
// Recovery requires:
//
// ✓ Existing Firebase user.
// ✓ Password provider.
// ✓ Existing usable JR CALL profile.
// ✓ Firebase Email/Profile Email consistency.
//
// Unknown/ineligible account -> null.
// ===============================================================

async function resolvePasswordRecoveryTarget(
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
      'JR CALL Password Recovery account lookup failed:',
      error,
    );

    throw new HttpsError(
      'unavailable',
      'Password recovery is temporarily unavailable.',
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
      'JR CALL recovery profile/Auth Email mismatch.',
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
// No real challenge is persisted for unknown/ineligible accounts.
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
// PASSWORD RECOVERY RATE DOCUMENT ID
// ===============================================================

function buildRateDocumentId({
  uid,
  email,
  purpose,
  ipHash,
}) {
  return sha256(
    [
      'password-recovery',
      uid,
      purpose,
      email,
      ipHash || '',
    ].join('|'),
  );
}

// ===============================================================
// RESERVE PASSWORD RECOVERY CHALLENGE
// ===============================================================

async function reservePasswordRecoveryChallenge({
  uid,
  email,
  challengeId,
  otpHash,
  ipHash,
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

  const rateRef =
    db
      .collection(
        PASSWORD_RECOVERY_RATE_COLLECTION,
      )
      .doc(
        buildRateDocumentId({
          uid,

          email,

          purpose:
            PASSWORD_RECOVERY_PURPOSE,

          ipHash,
        }),
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

          if (
            isTimestamp(
              rateData.lastSentAt,
            )
          ) {
            lastSentAt =
              rateData.lastSentAt;
          }
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
            'Please wait before requesting another recovery OTP.',
            {
              retryAfterSeconds,
            },
          );
        }
      }

      // ---------------------------------------------------------
      // MAX SENDS
      // ---------------------------------------------------------

      if (
        sendCount >=
        OTP_MAX_SENDS_PER_WINDOW
      ) {
        throw new HttpsError(
          'resource-exhausted',
          'Too many recovery requests. Please try again later.',
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

          purpose:
            PASSWORD_RECOVERY_PURPOSE,

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

          purpose:
            PASSWORD_RECOVERY_PURPOSE,

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
// SEND PASSWORD RECOVERY EMAIL
// ===============================================================

async function sendRecoveryEmail({
  apiKey,
  from,
  email,
  otp,
  challengeId,
}) {
  const subject =
    'Your JR CALL password recovery code';

  const text =
    [
      'JR CALL',
      '',
      `Your password recovery code is ${otp}.`,
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
<title>JR CALL Password Recovery</title>
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
        Secure Password Recovery
      </div>

      <div style="
        margin-top:30px;
        text-align:center;
        color:#374151;
        font-size:15px;
      ">
        Your password recovery code is:
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
        Never share this recovery code with anyone.
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
            `jr-call-recovery/${challengeId}`,
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
      'JR CALL recovery Email provider rejected request:',
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
// MARK RECOVERY DELIVERY SUCCESS
// ===============================================================

async function markChallengeDelivered({
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
// MARK RECOVERY DELIVERY FAILURE
// ===============================================================

async function markChallengeDeliveryFailed({
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
      'JR CALL failed to mark recovery delivery failure:',
      error,
    );
  }
}

// ===============================================================
// PASSWORD RECOVERY — SEND
//
// Enumeration-resistant.
//
// Unknown/ineligible account gets generic accepted response.
//
// No password exists in this request.
// ===============================================================

async function sendPasswordRecoveryOtpHandler(
  request,
) {
  const data =
    callableData(
      request,
    );

  const email =
    normalizeEmail(
      data.email,
    );

  if (
    !isValidEmail(
      email,
    )
  ) {
    throw new HttpsError(
      'invalid-argument',
      'A valid Email address is required.',
    );
  }

  const target =
    await resolvePasswordRecoveryTarget(
      email,
    );

  if (!target) {
    return createDecoyAcceptedResponse();
  }

  const {
    resendApiKey,
    hashSecret,
    emailFrom,
  } =
    requireEmailBackendConfiguration();

  const challengeId =
    createChallengeId();

  const otp =
    createSixDigitOtp();

  const otpHash =
    createOtpHash({
      challengeId,

      uid:
        target.uid,

      email:
        target.email,

      purpose:
        PASSWORD_RECOVERY_PURPOSE,

      otp,

      secret:
        hashSecret,
    });

  const {
    challengeRef,
  } =
    await reservePasswordRecoveryChallenge({
      uid:
        target.uid,

      email:
        target.email,

      challengeId,

      otpHash,

      ipHash:
        resolveIpHash(
          request,
        ),
    });

  try {
    const delivery =
      await sendRecoveryEmail({
        apiKey:
          resendApiKey,

        from:
          emailFrom,

        email:
          target.email,

        otp,

        challengeId,
      });

    await markChallengeDelivered({
      challengeRef,

      messageId:
        delivery.messageId,
    });
  } catch (error) {
    await markChallengeDeliveryFailed({
      challengeRef,
    });

    console.error(
      'JR CALL Password Recovery OTP delivery failed:',
      error,
    );

    throw new HttpsError(
      'unavailable',
      'Password recovery OTP could not be delivered. Please try again.',
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
// ACQUIRE OTP CHALLENGE
//
// CRITICAL TRANSACTION CONTRACT:
//
// State-changing rejection is NOT thrown inside the Firestore
// transaction.
//
// Instead:
//
// 1. Update transaction state.
// 2. Let transaction commit.
// 3. Throw HttpsError after commit.
//
// Therefore:
//
// ✓ Wrong-attempt count persists.
// ✓ Expired state persists.
// ✓ Locked state persists.
// ✓ Lease ownership remains deterministic.
// ===============================================================

async function acquireOtpChallenge({
  request,
  challengeId,
  otp,
  expectedPurpose,
  requireAuthentication,
}) {
  const hashSecret =
    requireOtpHashSecret();

  const challengeRef =
    db
      .collection(
        EMAIL_OTP_COLLECTION,
      )
      .doc(
        challengeId,
      );

  const authenticatedUid =
    requireAuthentication
      ? requireCallableUid(
          request,
        )
      : optionalCallableUid(
          request,
        );

  const now =
    Timestamp.now();

  const leaseId =
    createLeaseId();

  const leaseExpiresAt =
    secondsFromNow(
      OTP_FINALIZATION_LEASE_SECONDS,
    );

  let acquiredData =
    null;

  let rejection =
    null;

  await db.runTransaction(
    async (transaction) => {
      const snapshot =
        await transaction.get(
          challengeRef,
        );

      // ---------------------------------------------------------
      // CHALLENGE MISSING
      // ---------------------------------------------------------

      if (!snapshot.exists) {
        rejection = {
          code:
            'not-found',

          message:
            'The OTP challenge was not found or has expired.',
        };

        return;
      }

      const challenge =
        snapshot.data() ||
        {};

      const storedUid =
        cleanString(
          challenge.uid,
        );

      const storedEmail =
        normalizeEmail(
          challenge.email,
        );

      const storedPurpose =
        normalizePurpose(
          challenge.purpose,
        );

      const storedOtpHash =
        cleanString(
          challenge.otpHash,
        );

      // ---------------------------------------------------------
      // STRUCTURE VALIDATION
      // ---------------------------------------------------------

      if (
        storedUid === '' ||
        !isValidEmail(
          storedEmail,
        ) ||
        storedPurpose !==
          expectedPurpose ||
        storedOtpHash === ''
      ) {
        rejection = {
          code:
            'failed-precondition',

          message:
            'The OTP challenge is invalid.',
        };

        return;
      }

      // ---------------------------------------------------------
      // AUTHENTICATED OWNERSHIP
      // ---------------------------------------------------------

      if (
        requireAuthentication &&
        authenticatedUid !==
          storedUid
      ) {
        rejection = {
          code:
            'permission-denied',

          message:
            'This OTP challenge does not belong to the authenticated account.',
        };

        return;
      }

      // ---------------------------------------------------------
      // SINGLE USE
      // ---------------------------------------------------------

      if (
        challenge.used === true
      ) {
        rejection = {
          code:
            'failed-precondition',

          message:
            'This OTP has already been used.',
        };

        return;
      }

      // ---------------------------------------------------------
      // DELIVERY FAILURE
      // ---------------------------------------------------------

      if (
        challenge.deliveryStatus ===
          'failed' ||
        challenge.verificationStatus ===
          'delivery_failed'
      ) {
        rejection = {
          code:
            'failed-precondition',

          message:
            'This OTP was not successfully delivered.',
        };

        return;
      }

      // ---------------------------------------------------------
      // EXPIRY
      // ---------------------------------------------------------

      const expiresAtMillis =
        timestampToMillis(
          challenge.expiresAt,
        );

      if (
        expiresAtMillis === 0 ||
        now.toMillis() >=
          expiresAtMillis
      ) {
        transaction.update(
          challengeRef,
          {
            verificationStatus:
              'expired',

            expiredAt:
              now,

            finalizationLeaseId:
              null,

            finalizationLeaseExpiresAt:
              null,
          },
        );

        rejection = {
          code:
            'deadline-exceeded',

          message:
            'The OTP has expired. Request a new code.',
        };

        return;
      }

      // ---------------------------------------------------------
      // ATTEMPTS
      // ---------------------------------------------------------

      const attempts =
        Number.isInteger(
          challenge.attempts,
        )
          ? Math.max(
              challenge.attempts,
              0,
            )
          : 0;

      const maxAttempts =
        Number.isInteger(
          challenge.maxAttempts,
        ) &&
        challenge.maxAttempts > 0
          ? challenge.maxAttempts
          : OTP_MAX_VERIFY_ATTEMPTS;

      if (
        attempts >= maxAttempts
      ) {
        if (
          challenge.verificationStatus !==
          'locked'
        ) {
          transaction.update(
            challengeRef,
            {
              verificationStatus:
                'locked',

              lockedAt:
                now,

              finalizationLeaseId:
                null,

              finalizationLeaseExpiresAt:
                null,
            },
          );
        }

        rejection = {
          code:
            'resource-exhausted',

          message:
            'Too many OTP verification attempts.',
        };

        return;
      }

      // ---------------------------------------------------------
      // ACTIVE FINALIZATION LEASE
      // ---------------------------------------------------------

      const existingLeaseId =
        cleanString(
          challenge.finalizationLeaseId,
        );

      const existingLeaseExpiresAtMillis =
        timestampToMillis(
          challenge.finalizationLeaseExpiresAt,
        );

      if (
        challenge.verificationStatus ===
          'finalizing' &&
        existingLeaseId !== '' &&
        existingLeaseExpiresAtMillis >
          now.toMillis()
      ) {
        rejection = {
          code:
            'failed-precondition',

          message:
            'OTP finalization is already in progress.',
        };

        return;
      }

      // ---------------------------------------------------------
      // OTP HASH
      // ---------------------------------------------------------

      const suppliedHash =
        createOtpHash({
          challengeId,

          uid:
            storedUid,

          email:
            storedEmail,

          purpose:
            storedPurpose,

          otp,

          secret:
            hashSecret,
        });

      // ---------------------------------------------------------
      // INCORRECT OTP
      // ---------------------------------------------------------

      if (
        !timingSafeHashEquals(
          storedOtpHash,
          suppliedHash,
        )
      ) {
        const nextAttempts =
          attempts + 1;

        const exhausted =
          nextAttempts >=
          maxAttempts;

        transaction.update(
          challengeRef,
          {
            attempts:
              nextAttempts,

            verificationStatus:
              exhausted
                ? 'locked'
                : 'pending',

            lastFailedAttemptAt:
              now,

            ...(exhausted
              ? {
                  lockedAt:
                    now,
                }
              : {}),

            finalizationLeaseId:
              null,

            finalizationLeaseExpiresAt:
              null,
          },
        );

        rejection = {
          code:
            exhausted
              ? 'resource-exhausted'
              : 'permission-denied',

          message:
            exhausted
              ? 'Too many OTP verification attempts.'
              : 'The OTP is incorrect.',
        };

        return;
      }

      // ---------------------------------------------------------
      // CORRECT OTP — ACQUIRE FINALIZATION LEASE
      // ---------------------------------------------------------

      transaction.update(
        challengeRef,
        {
          verificationStatus:
            'finalizing',

          verifiedAt:
            now,

          finalizationLeaseId:
            leaseId,

          finalizationLeaseExpiresAt:
            leaseExpiresAt,
        },
      );

      acquiredData = {
        challengeRef,

        uid:
          storedUid,

        email:
          storedEmail,

        purpose:
          storedPurpose,

        leaseId,
      };
    },
  );

  // -------------------------------------------------------------
  // THROW ONLY AFTER TRANSACTION COMMIT
  // -------------------------------------------------------------

  if (rejection !== null) {
    throw new HttpsError(
      rejection.code,
      rejection.message,
    );
  }

  if (!acquiredData) {
    throw new HttpsError(
      'internal',
      'OTP verification could not be finalized.',
    );
  }

  return acquiredData;
}

// ===============================================================
// RELEASE FINALIZATION LEASE
//
// Called only when OTP itself was valid but final account mutation
// failed.
//
// The OTP therefore becomes retryable until:
// - expiry,
// - attempt exhaustion,
// - or successful single-use finalization.
// ===============================================================

async function releaseFinalizationLease({
  challengeRef,
  leaseId,
}) {
  try {
    await db.runTransaction(
      async (transaction) => {
        const snapshot =
          await transaction.get(
            challengeRef,
          );

        if (!snapshot.exists) {
          return;
        }

        const data =
          snapshot.data() ||
          {};

        if (
          data.used === true
        ) {
          return;
        }

        if (
          cleanString(
            data.finalizationLeaseId,
          ) !== leaseId
        ) {
          return;
        }

        transaction.update(
          challengeRef,
          {
            verificationStatus:
              'pending',

            finalizationLeaseId:
              null,

            finalizationLeaseExpiresAt:
              null,
          },
        );
      },
    );
  } catch (error) {
    console.error(
      'JR CALL OTP lease release failed:',
      error,
    );
  }
}

// ===============================================================
// MARK CHALLENGE USED
//
// Successful finalization permanently invalidates the challenge
// and removes its OTP hash.
// ===============================================================

async function markChallengeUsed({
  challengeRef,
  leaseId,
}) {
  await db.runTransaction(
    async (transaction) => {
      const snapshot =
        await transaction.get(
          challengeRef,
        );

      if (!snapshot.exists) {
        throw new HttpsError(
          'not-found',
          'OTP challenge no longer exists.',
        );
      }

      const data =
        snapshot.data() ||
        {};

      if (
        data.used === true
      ) {
        return;
      }

      if (
        cleanString(
          data.finalizationLeaseId,
        ) !== leaseId
      ) {
        throw new HttpsError(
          'failed-precondition',
          'OTP finalization ownership was lost.',
        );
      }

      transaction.update(
        challengeRef,
        {
          used:
            true,

          verificationStatus:
            'used',

          usedAt:
            Timestamp.now(),

          finalizationLeaseId:
            null,

          finalizationLeaseExpiresAt:
            null,

          otpHash:
            FieldValue.delete(),
        },
      );
    },
  );
}

// ===============================================================
// EMAIL OTP — VERIFY
//
// IMPORTANT:
//
// CURRENT NORMAL EMAIL LOGIN DOES NOT REQUIRE THIS.
//
// emailLogin support remains compatibility-only.
//
// emailSignUp / emailChange remain available for existing settings
// or transitional flows.
//
// No standalone Email UID is created here.
// ===============================================================

async function verifyEmailOtpHandler(
  request,
) {
  const data =
    callableData(
      request,
    );

  const challengeId =
    normalizeChallengeId(
      data.challengeId,
    );

  const otp =
    normalizeOtp(
      data.otp,
    );

  const purpose =
    normalizePurpose(
      data.purpose,
    );

  // -------------------------------------------------------------
  // INPUT VALIDATION
  // -------------------------------------------------------------

  if (
    challengeId === '' ||
    challengeId.length > 256
  ) {
    throw new HttpsError(
      'invalid-argument',
      'A valid OTP challenge ID is required.',
    );
  }

  if (
    !isValidOtp(
      otp,
    )
  ) {
    throw new HttpsError(
      'invalid-argument',
      'OTP must contain exactly 6 digits.',
    );
  }

  if (
    !STANDARD_EMAIL_PURPOSES.has(
      purpose,
    )
  ) {
    throw new HttpsError(
      'invalid-argument',
      'Unsupported Email OTP purpose.',
    );
  }

  // -------------------------------------------------------------
  // ALL STANDARD EMAIL OTP CHALLENGES ARE UID-BOUND
  // -------------------------------------------------------------

  const acquired =
    await acquireOtpChallenge({
      request,

      challengeId,

      otp,

      expectedPurpose:
        purpose,

      requireAuthentication:
        true,
    });

  try {
    let firebaseUser;

    try {
      firebaseUser =
        await getAuth()
          .getUser(
            acquired.uid,
          );
    } catch (error) {
      if (
        error?.code ===
        'auth/user-not-found'
      ) {
        throw new HttpsError(
          'not-found',
          'The Firebase account no longer exists.',
        );
      }

      throw error;
    }

    if (
      firebaseUser.disabled === true
    ) {
      throw new HttpsError(
        'permission-denied',
        'This account is unavailable.',
      );
    }

    // -----------------------------------------------------------
    // EMAIL LOGIN — LEGACY COMPATIBILITY ONLY
    //
    // Normal current LoginScreen:
    //
    // Email + Password
    //      ↓
    // AuthService.signInWithEmailPassword()
    //      ↓
    // direct authenticated session
    //
    // It must not require this branch.
    // -----------------------------------------------------------

    if (
      purpose ===
      EMAIL_LOGIN_PURPOSE
    ) {
      if (
        !hasPasswordProvider(
          firebaseUser,
        )
      ) {
        throw new HttpsError(
          'failed-precondition',
          'Email Login is not available for this account.',
        );
      }

      const authenticatedEmail =
        normalizeEmail(
          firebaseUser.email,
        );

      if (
        authenticatedEmail === '' ||
        authenticatedEmail !==
          acquired.email
      ) {
        throw new HttpsError(
          'permission-denied',
          'Authenticated Email does not match this OTP challenge.',
        );
      }

      const profile =
        await getUsableExistingProfile(
          acquired.uid,
        );

      if (!profile) {
        throw new HttpsError(
          'failed-precondition',
          'The JR CALL profile is unavailable.',
        );
      }
    }

    // -----------------------------------------------------------
    // EMAIL SIGNUP COMPATIBILITY
    //
    // Phone identity must remain attached to this same Firebase UID.
    // -----------------------------------------------------------

    if (
      purpose ===
      EMAIL_SIGNUP_PURPOSE
    ) {
      const phoneNumber =
        cleanString(
          firebaseUser.phoneNumber,
        );

      if (
        phoneNumber === '' ||
        !hasPhoneProvider(
          firebaseUser,
        )
      ) {
        throw new HttpsError(
          'failed-precondition',
          'A Firebase-verified Phone Number is required before adding Email.',
        );
      }
    }

    // -----------------------------------------------------------
    // EMAIL SIGNUP / EMAIL CHANGE
    //
    // Backend marks requested Email as Firebase-verified for this
    // SAME Firebase UID.
    //
    // Password provider linking remains AuthService/client-owned.
    // -----------------------------------------------------------

    if (
      purpose ===
        EMAIL_SIGNUP_PURPOSE ||
      purpose ===
        EMAIL_CHANGE_PURPOSE
    ) {
      try {
        firebaseUser =
          await getAuth()
            .updateUser(
              acquired.uid,
              {
                email:
                  acquired.email,

                emailVerified:
                  true,
              },
            );
      } catch (error) {
        if (
          error?.code ===
          'auth/email-already-exists'
        ) {
          throw new HttpsError(
            'already-exists',
            'This Email is already linked to another account.',
          );
        }

        if (
          error?.code ===
          'auth/user-not-found'
        ) {
          throw new HttpsError(
            'not-found',
            'The Firebase account no longer exists.',
          );
        }

        if (
          error?.code ===
          'auth/invalid-email'
        ) {
          throw new HttpsError(
            'invalid-argument',
            'The Email address is invalid.',
          );
        }

        throw error;
      }
    }

    // -----------------------------------------------------------
    // FINAL AUTH EMAIL VALIDATION
    // -----------------------------------------------------------

    const finalFirebaseEmail =
      normalizeEmail(
        firebaseUser.email,
      );

    if (
      finalFirebaseEmail === '' ||
      finalFirebaseEmail !==
        acquired.email
    ) {
      throw new HttpsError(
        'permission-denied',
        'Firebase Email state does not match this OTP challenge.',
      );
    }

    // -----------------------------------------------------------
    // FIRESTORE PROFILE
    //
    // Do not create a missing normal profile merely because an
    // Email OTP succeeded.
    // -----------------------------------------------------------

    const profile =
      await getUsableExistingProfile(
        acquired.uid,
      );

    if (!profile) {
      throw new HttpsError(
        'failed-precondition',
        'The JR CALL profile is unavailable.',
      );
    }

    const profileUpdate = {
      email:
        acquired.email,

      emailNormalized:
        acquired.email,

      verified:
        true,

      updatedAt:
        FieldValue.serverTimestamp(),
    };

    if (
      purpose ===
        EMAIL_SIGNUP_PURPOSE ||
      purpose ===
        EMAIL_CHANGE_PURPOSE ||
      firebaseUser.emailVerified ===
        true
    ) {
      profileUpdate.emailVerified =
        true;
    }

    await db
      .collection(
        USERS_COLLECTION,
      )
      .doc(
        acquired.uid,
      )
      .set(
        profileUpdate,
        {
          merge:
            true,
        },
      );

    // -----------------------------------------------------------
    // SINGLE USE
    // -----------------------------------------------------------

    await markChallengeUsed({
      challengeRef:
        acquired.challengeRef,

      leaseId:
        acquired.leaseId,
    });

    return {
      success:
        true,

      verified:
        true,

      challengeId,

      purpose,

      email:
        acquired.email,

      uid:
        acquired.uid,
    };
  } catch (error) {
    await releaseFinalizationLease({
      challengeRef:
        acquired.challengeRef,

      leaseId:
        acquired.leaseId,
    });

    if (
      error instanceof HttpsError
    ) {
      throw error;
    }

    console.error(
      'JR CALL Email OTP finalization failed:',
      error,
    );

    throw new HttpsError(
      'unavailable',
      'Email verification could not be finalized right now.',
    );
  }
}

// ===============================================================
// PASSWORD RECOVERY — VERIFY
//
// No authenticated Firebase client session is required.
//
// Security comes from:
// - UID-bound server challenge
// - Email-bound challenge
// - HMAC OTP
// - expiry
// - attempt limits
// - finalization lease
//
// Password exists only in request memory.
// ===============================================================

async function verifyPasswordRecoveryOtpHandler(
  request,
) {
  const data =
    callableData(
      request,
    );

  const challengeId =
    normalizeChallengeId(
      data.challengeId,
    );

  const otp =
    normalizeOtp(
      data.otp,
    );

  const newPassword =
    typeof data.newPassword ===
      'string'
      ? data.newPassword
      : '';

  // -------------------------------------------------------------
  // INPUT VALIDATION
  // -------------------------------------------------------------

  if (
    challengeId === '' ||
    challengeId.length > 256
  ) {
    throw new HttpsError(
      'invalid-argument',
      'A valid recovery challenge ID is required.',
    );
  }

  if (
    !isValidOtp(
      otp,
    )
  ) {
    throw new HttpsError(
      'invalid-argument',
      'OTP must contain exactly 6 digits.',
    );
  }

  if (
    !isValidPassword(
      newPassword,
    )
  ) {
    throw new HttpsError(
      'invalid-argument',
      'The new password must contain between 6 and 4096 characters.',
    );
  }

  // -------------------------------------------------------------
  // ACQUIRE RECOVERY CHALLENGE
  // -------------------------------------------------------------

  const acquired =
    await acquireOtpChallenge({
      request,

      challengeId,

      otp,

      expectedPurpose:
        PASSWORD_RECOVERY_PURPOSE,

      requireAuthentication:
        false,
    });

  try {
    let firebaseUser;

    try {
      firebaseUser =
        await getAuth()
          .getUser(
            acquired.uid,
          );
    } catch (error) {
      if (
        error?.code ===
        'auth/user-not-found'
      ) {
        throw new HttpsError(
          'not-found',
          'The Firebase account no longer exists.',
        );
      }

      throw error;
    }

    // -----------------------------------------------------------
    // ACCOUNT STATUS
    // -----------------------------------------------------------

    if (
      firebaseUser.disabled === true
    ) {
      throw new HttpsError(
        'permission-denied',
        'This account is unavailable.',
      );
    }

    // -----------------------------------------------------------
    // EMAIL + PROVIDER VALIDATION
    // -----------------------------------------------------------

    const firebaseEmail =
      normalizeEmail(
        firebaseUser.email,
      );

    if (
      firebaseEmail === '' ||
      firebaseEmail !==
        acquired.email ||
      !hasPasswordProvider(
        firebaseUser,
      )
    ) {
      throw new HttpsError(
        'failed-precondition',
        'Password recovery can no longer be completed.',
      );
    }

    // -----------------------------------------------------------
    // JR CALL PROFILE VALIDATION
    // -----------------------------------------------------------

    const profile =
      await getUsableExistingProfile(
        acquired.uid,
      );

    if (!profile) {
      throw new HttpsError(
        'failed-precondition',
        'Password recovery can no longer be completed.',
      );
    }

    const profileEmail =
      normalizeEmail(
        profile.emailNormalized ||
        profile.email ||
        '',
      );

    if (
      profileEmail !== '' &&
      profileEmail !==
        acquired.email
    ) {
      throw new HttpsError(
        'failed-precondition',
        'Password recovery account information changed.',
      );
    }

    // -----------------------------------------------------------
    // PASSWORD UPDATE
    //
    // Raw password:
    //
    // ✓ exists only in this request memory,
    // ✓ is sent to Firebase Admin updateUser(),
    // ✓ is never written to Firestore,
    // ✓ is never written to the OTP challenge.
    // -----------------------------------------------------------

    try {
      firebaseUser =
        await getAuth()
          .updateUser(
            acquired.uid,
            {
              password:
                newPassword,
            },
          );
    } catch (error) {
      if (
        error?.code ===
        'auth/user-not-found'
      ) {
        throw new HttpsError(
          'not-found',
          'The Firebase account no longer exists.',
        );
      }

      if (
        error?.code ===
        'auth/invalid-password'
      ) {
        throw new HttpsError(
          'invalid-argument',
          'The new password is not valid.',
        );
      }

      throw error;
    }

    // -----------------------------------------------------------
    // CONFIRM PASSWORD PROVIDER STILL EXISTS
    // -----------------------------------------------------------

    if (
      !hasPasswordProvider(
        firebaseUser,
      )
    ) {
      throw new HttpsError(
        'failed-precondition',
        'The Email/Password provider is unavailable.',
      );
    }

    // -----------------------------------------------------------
    // REVOKE EXISTING REFRESH TOKENS
    //
    // Password reset intentionally invalidates prior long-lived
    // refresh sessions for account security.
    //
    // Normal Login itself does NOT revoke other device sessions.
    // -----------------------------------------------------------

    await getAuth()
      .revokeRefreshTokens(
        acquired.uid,
      );

    // -----------------------------------------------------------
    // FIRESTORE METADATA
    //
    // Never persist the actual password.
    // -----------------------------------------------------------

    await db
      .collection(
        USERS_COLLECTION,
      )
      .doc(
        acquired.uid,
      )
      .set(
        {
          updatedAt:
            FieldValue.serverTimestamp(),

          passwordUpdatedAt:
            FieldValue.serverTimestamp(),
        },
        {
          merge:
            true,
        },
      );

    // -----------------------------------------------------------
    // SINGLE USE
    // -----------------------------------------------------------

    await markChallengeUsed({
      challengeRef:
        acquired.challengeRef,

      leaseId:
        acquired.leaseId,
    });

    return {
      success:
        true,

      verified:
        true,

      passwordReset:
        true,

      challengeId,

      purpose:
        PASSWORD_RECOVERY_PURPOSE,
    };
  } catch (error) {
    await releaseFinalizationLease({
      challengeRef:
        acquired.challengeRef,

      leaseId:
        acquired.leaseId,
    });

    if (
      error instanceof HttpsError
    ) {
      throw error;
    }

    console.error(
      'JR CALL Password Recovery finalization failed:',
      error,
    );

    throw new HttpsError(
      'unavailable',
      'Password recovery could not be finalized right now.',
    );
  }
}

// ===============================================================
// EXPORTS
// ===============================================================

module.exports = {
  verifyEmailOtpHandler,
  sendPasswordRecoveryOtpHandler,
  verifyPasswordRecoveryOtpHandler,
};

// ===============================================================
// END OF FILE
//
// OTP / AUTH MASTER FILE 08 / 09
//
// FINAL CONTRACT:
//
// PHONE:
//
// ✓ Phone OTP is not generated here.
// ✓ Phone OTP is not verified here.
// ✓ Phone OTP is not persisted here.
// ✓ No Phone password.
// ✓ No fake/local Phone OTP.
// ✓ Firebase Authentication remains Phone OTP authority.
//
// EMAIL LOGIN:
//
// ✓ Current normal Email Login = Email + Password.
// ✓ No Email OTP required for normal Login.
// ✓ No Email verification gate required for normal Login.
// ✓ emailLogin OTP remains compatibility-only.
//
// ACCOUNT CREATION:
//
// ✓ Phone remains mandatory canonical account identity.
// ✓ Email remains optional.
// ✓ Standalone Email account creation is not created here.
// ✓ Email OTP compatibility cannot create a Phone-less JR CALL UID.
// ✓ Email/Password linking remains SAME Firebase UID.
//
// EMAIL OTP:
//
// ✓ Email Signup compatibility verification preserved.
// ✓ Email Login compatibility verification preserved.
// ✓ Email Change verification preserved.
// ✓ UID-bound OTP challenge.
// ✓ Raw OTP never persisted.
// ✓ HMAC-SHA256.
// ✓ Timing-safe comparison.
// ✓ Five-minute expiry.
// ✓ Five verification attempts.
// ✓ Single-use enforcement.
// ✓ Finalization lease.
// ✓ Failed attempt transaction persistence fixed.
// ✓ Expiry transaction persistence fixed.
// ✓ Lock transaction persistence fixed.
//
// PASSWORD RECOVERY:
//
// ✓ Password Recovery Email OTP send preserved.
// ✓ Password Recovery Email OTP verify preserved.
// ✓ Enumeration-resistant send.
// ✓ Five sends per fifteen-minute rate window.
// ✓ Sixty-second resend cooldown.
// ✓ IP rate-limit dimension preserved.
// ✓ Firebase Admin password update preserved.
// ✓ Refresh-token revocation preserved.
// ✓ Password never persisted in Firestore.
// ✓ Password never persisted in OTP challenge.
//
// MULTI-DEVICE:
//
// ✓ Normal Login does not revoke other Firebase sessions here.
// ✓ Password Recovery intentionally revokes refresh tokens.
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
// functions/managers/otp_manager_part2.js
//
// NEXT / FINAL BACKEND FILE:
//
// functions/index.js
// ===============================================================
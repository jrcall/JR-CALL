'use strict';

// ===============================================================
// JR CALL
// File: index.js
// Location: functions/index.js
// Master Repair: FILE 02
//
// PURPOSE:
// Production Firebase Cloud Functions backend.
//
// OWNS:
// - Existing Phone account lookup
// - JR CALL secure Email OTP
// - Email signup/login/change verification
// - Link-free password recovery Email OTP
// - TURN temporary credentials
//
// PHONE OTP:
// Flutter -> Firebase Authentication directly.
//
// EMAIL OTP:
// Flutter -> Cloud Functions here.
//
// SECURITY:
// - Raw OTP is NEVER stored.
// - Raw OTP is NEVER returned.
// - OTP is HMAC-SHA256 hashed.
// - Password reset password is NEVER stored.
// - Firebase UID is canonical private account identity.
// - TURN secrets remain server-side.
//
// RESOURCE POLICY:
// - Current project regional CPU quota is respected.
// - Auth/OTP functions use maximum 10 instances.
// - TURN endpoint uses maximum 5 instances.
// - TURN configuration never blocks Auth/OTP.
// ===============================================================

const crypto = require('crypto');

const { initializeApp } = require('firebase-admin/app');

const { getAuth } = require('firebase-admin/auth');

const {
  getFirestore,
  FieldValue,
  Timestamp,
} = require('firebase-admin/firestore');

const {
  onCall,
  onRequest,
  HttpsError,
} = require('firebase-functions/v2/https');

const {
  defineSecret,
  defineString,
} = require('firebase-functions/params');

// ===============================================================
// FIREBASE ADMIN
// ===============================================================

initializeApp();

const db = getFirestore();

// ===============================================================
// REGION
// ===============================================================

const FUNCTIONS_REGION = 'us-central1';

// ===============================================================
// CLOUD RESOURCE POLICY
// ===============================================================
//
// IMPORTANT:
//
// 256MiB 2nd-gen Functions may be provisioned with approximately
// 1 vCPU per instance.
//
// The current Google Cloud regional CPU quota previously rejected:
//
// maxInstances: 50
//
// because that requested:
// 50,000 mCPU
//
// while the project currently allows:
// 20,000 mCPU.
//
// These values deliberately stay below that limit.
//
// ===============================================================

const CALLABLE_MAX_INSTANCES = 10;

const TURN_MAX_INSTANCES = 5;

// ===============================================================
// COLLECTIONS
// ===============================================================

const USERS_COLLECTION = 'users';

const EMAIL_OTP_COLLECTION = 'email_otp_challenges';

const EMAIL_OTP_RATE_COLLECTION = 'email_otp_rate_limits';

const PASSWORD_RECOVERY_RATE_COLLECTION =
  'password_recovery_rate_limits';

const PHONE_LOOKUP_RATE_COLLECTION =
  'phone_lookup_rate_limits';

// ===============================================================
// EMAIL CONFIGURATION
// ===============================================================

const RESEND_API_KEY =
  defineSecret('RESEND_API_KEY');

const EMAIL_OTP_HASH_SECRET =
  defineSecret('EMAIL_OTP_HASH_SECRET');

const EMAIL_OTP_FROM =
  defineString('EMAIL_OTP_FROM', {
    default: '',
  });

// ===============================================================
// TURN CONFIGURATION
// ===============================================================

const TURN_SHARED_SECRET =
  defineSecret('TURN_SHARED_SECRET');

const TURN_PRIMARY_HOST =
  defineString('TURN_PRIMARY_HOST', {
    default: '',
  });

const TURN_BACKUP_HOST =
  defineString('TURN_BACKUP_HOST', {
    default: '',
  });

const TURN_TTL_SECONDS =
  defineString('TURN_TTL_SECONDS', {
    default: '3600',
  });

// ===============================================================
// OTP POLICY
// ===============================================================

const OTP_LENGTH = 6;

const OTP_EXPIRY_SECONDS = 5 * 60;

const OTP_RESEND_COOLDOWN_SECONDS = 60;

const OTP_RATE_WINDOW_SECONDS = 15 * 60;

const OTP_MAX_SENDS_PER_WINDOW = 5;

const OTP_MAX_VERIFY_ATTEMPTS = 5;

const AUTHENTICATED_EMAIL_OTP_PURPOSES =
  new Set([
    'emailSignUp',
    'emailLogin',
    'emailChange',
  ]);

const PASSWORD_RECOVERY_PURPOSE =
  'passwordRecovery';

// ===============================================================
// PHONE LOOKUP POLICY
// ===============================================================

const PHONE_LOOKUP_WINDOW_SECONDS = 10 * 60;

const PHONE_LOOKUP_MAX_REQUESTS = 30;

// ===============================================================
// NORMALIZATION
// ===============================================================

function cleanString(value) {
  return typeof value === 'string'
    ? value.trim()
    : '';
}

function normalizeEmail(value) {
  return cleanString(value).toLowerCase();
}

function normalizePurpose(value) {
  return cleanString(value);
}

function normalizeChallengeId(value) {
  return cleanString(value);
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
    .replace(/\s+/g, '');
}

function normalizePhoneNumber(value) {
  if (typeof value !== 'string') {
    return '';
  }

  return value
    .trim()
    .replace(/[\s()\-.]/g, '');
}

function normalizePhoneForSearch(value) {
  const normalized =
    normalizePhoneNumber(value);

  if (normalized === '') {
    return '';
  }

  if (!normalized.startsWith('+')) {
    return normalized.replace(
      /[^0-9]/g,
      '',
    );
  }

  const digits =
    normalized
      .substring(1)
      .replace(
        /[^0-9]/g,
        '',
      );

  return digits === ''
    ? ''
    : `+${digits}`;
}

// ===============================================================
// VALIDATION
// ===============================================================

function isValidEmail(value) {
  return (
    typeof value === 'string' &&
    value.length > 3 &&
    value.length <= 254 &&
    /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(value)
  );
}

function isValidOtp(value) {
  return new RegExp(
    `^\\d{${OTP_LENGTH}}$`,
  ).test(value);
}

function isValidE164Phone(value) {
  return /^\+[1-9][0-9]{7,14}$/.test(value);
}

function isValidPassword(value) {
  return (
    typeof value === 'string' &&
    value.length >= 6 &&
    value.length <= 4096
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
    Date.now() + seconds * 1000,
  );
}

// ===============================================================
// HASH / RANDOM
// ===============================================================

function sha256(value) {
  return crypto
    .createHash('sha256')
    .update(String(value))
    .digest('hex');
}

function createChallengeId() {
  return crypto.randomUUID();
}

function createSixDigitOtp() {
  return crypto
    .randomInt(0, 1000000)
    .toString()
    .padStart(
      OTP_LENGTH,
      '0',
    );
}

function createOtpHash({
  challengeId,
  uid,
  email,
  purpose,
  otp,
  secret,
}) {
  const payload = [
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
    .update(payload)
    .digest('hex');
}

function timingSafeHashEquals(
  storedHash,
  suppliedHash,
) {
  if (
    typeof storedHash !== 'string' ||
    typeof suppliedHash !== 'string' ||
    !/^[a-f0-9]{64}$/i.test(storedHash) ||
    !/^[a-f0-9]{64}$/i.test(suppliedHash)
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
    stored.length !== supplied.length
  ) {
    return false;
  }

  return crypto.timingSafeEqual(
    stored,
    supplied,
  );
}

// ===============================================================
// CALLABLE HELPERS
// ===============================================================

function callableData(request) {
  if (
    request &&
    request.data &&
    typeof request.data === 'object' &&
    !Array.isArray(request.data)
  ) {
    return request.data;
  }

  return {};
}

function requireCallableUid(request) {
  const uid =
    request &&
    request.auth &&
    typeof request.auth.uid === 'string'
      ? request.auth.uid.trim()
      : '';

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
    request &&
    request.rawRequest
      ? request.rawRequest
      : null;

  if (!rawRequest) {
    return 'unknown';
  }

  const forwarded =
    rawRequest.headers &&
    typeof rawRequest.headers[
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
      .substring(0, 128);
  }

  const ip =
    typeof rawRequest.ip === 'string'
      ? rawRequest.ip.trim()
      : '';

  return ip === ''
    ? 'unknown'
    : ip.substring(0, 128);
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
      'JR CALL Email OTP backend configuration is incomplete.',
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
// PHONE LOOKUP RATE LIMIT
// ===============================================================

async function enforcePhoneLookupRateLimit(
  request,
) {
  const ipHash =
    sha256(
      resolveClientIp(request),
    );

  const reference =
    db
      .collection(
        PHONE_LOOKUP_RATE_COLLECTION,
      )
      .doc(ipHash);

  const now =
    Timestamp.now();

  await db.runTransaction(
    async (transaction) => {
      const snapshot =
        await transaction.get(
          reference,
        );

      let count = 0;

      let windowStartedAt =
        now;

      if (snapshot.exists) {
        const data =
          snapshot.data() || {};

        const storedCount =
          Number.isInteger(
            data.count,
          )
            ? data.count
            : 0;

        const startMillis =
          timestampToMillis(
            data.windowStartedAt,
          );

        const expired =
          startMillis === 0 ||
          (
            now.toMillis() -
            startMillis
          ) >=
          (
            PHONE_LOOKUP_WINDOW_SECONDS *
            1000
          );

        if (!expired) {
          count =
            storedCount;

          windowStartedAt =
            data.windowStartedAt;
        }
      }

      if (
        count >=
        PHONE_LOOKUP_MAX_REQUESTS
      ) {
        throw new HttpsError(
          'resource-exhausted',
          'Too many verification requests. Please try again later.',
        );
      }

      transaction.set(
        reference,
        {
          ipHash,

          count:
            count + 1,

          windowStartedAt,

          updatedAt:
            now,
        },
        {
          merge: true,
        },
      );
    },
  );
}

// ===============================================================
// CHECK EXISTING PHONE ACCOUNT
// ===============================================================

exports.checkPhoneAccountExists =
  onCall(
    {
      region:
        FUNCTIONS_REGION,

      memory:
        '256MiB',

      timeoutSeconds:
        15,

      maxInstances:
        CALLABLE_MAX_INSTANCES,
    },

    async (request) => {
      const data =
        callableData(request);

      const phoneNumber =
        normalizePhoneNumber(
          data.phoneNumber,
        );

      if (
        !isValidE164Phone(
          phoneNumber,
        )
      ) {
        throw new HttpsError(
          'invalid-argument',
          'A valid international Phone Number is required.',
        );
      }

      await enforcePhoneLookupRateLimit(
        request,
      );

      let firebaseUser;

      try {
        firebaseUser =
          await getAuth()
            .getUserByPhoneNumber(
              phoneNumber,
            );
      } catch (error) {
        if (
          error &&
          error.code ===
            'auth/user-not-found'
        ) {
          return {
            exists: false,
          };
        }

        console.error(
          'JR CALL Phone Auth lookup failed:',
          error,
        );

        throw new HttpsError(
          'unavailable',
          'Phone account verification is temporarily unavailable.',
        );
      }

      if (
        !firebaseUser ||
        cleanString(
          firebaseUser.uid,
        ) === ''
      ) {
        return {
          exists: false,
        };
      }

      const userSnapshot =
        await db
          .collection(
            USERS_COLLECTION,
          )
          .doc(
            firebaseUser.uid,
          )
          .get();

      if (!userSnapshot.exists) {
        return {
          exists: false,
        };
      }

      const profile =
        userSnapshot.data() || {};

      if (
        profile.isDeleted === true ||
        profile.isBlocked === true
      ) {
        return {
          exists: false,
        };
      }

      const storedPhone =
        normalizePhoneForSearch(
          profile.phoneNormalized ||
          profile.phoneNumber ||
          profile.phone ||
          '',
        );

      const requestedPhone =
        normalizePhoneForSearch(
          phoneNumber,
        );

      if (
        storedPhone !== '' &&
        storedPhone !== requestedPhone
      ) {
        return {
          exists: false,
        };
      }

      return {
        exists: true,
      };
    },
  );

// ===============================================================
// OTP RATE DOCUMENT
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
// OTP CHALLENGE RESERVATION
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

  const rateRef =
    db
      .collection(
        rateCollection,
      )
      .doc(
        buildOtpRateDocumentId({
          namespace:
            rateNamespace,

          uid,

          email,

          purpose,

          ipHash,
        }),
      );

  await db.runTransaction(
    async (transaction) => {
      const rateSnapshot =
        await transaction.get(
          rateRef,
        );

      let sendCount = 0;

      let windowStartedAt =
        now;

      let lastSentAt = null;

      if (rateSnapshot.exists) {
        const rateData =
          rateSnapshot.data() || {};

        const storedCount =
          Number.isInteger(
            rateData.sendCount,
          )
            ? rateData.sendCount
            : 0;

        const windowStartMillis =
          timestampToMillis(
            rateData.windowStartedAt,
          );

        const windowExpired =
          windowStartMillis === 0 ||
          (
            now.toMillis() -
            windowStartMillis
          ) >=
          (
            OTP_RATE_WINDOW_SECONDS *
            1000
          );

        if (!windowExpired) {
          sendCount =
            storedCount;

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

      if (
        lastSentAt !== null
      ) {
        const elapsed =
          now.toMillis() -
          lastSentAt.toMillis();

        const cooldownMillis =
          OTP_RESEND_COOLDOWN_SECONDS *
          1000;

        if (
          elapsed <
          cooldownMillis
        ) {
          const retryAfterSeconds =
            Math.ceil(
              (
                cooldownMillis -
                elapsed
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

      if (
        sendCount >=
        OTP_MAX_SENDS_PER_WINDOW
      ) {
        throw new HttpsError(
          'resource-exhausted',
          'Too many Email OTP requests. Please try again later.',
        );
      }

      transaction.set(
        challengeRef,
        {
          challengeId,

          uid,

          email,

          emailHash:
            sha256(email),

          purpose,

          otpHash,

          attempts:
            0,

          maxAttempts:
            OTP_MAX_VERIFY_ATTEMPTS,

          used:
            false,

          deliveryStatus:
            'pending',

          verificationStatus:
            'pending',

          createdAt:
            now,

          expiresAt,

          verifiedAt:
            null,

          usedAt:
            null,

          deliveryMessageId:
            null,

          ipHash:
            ipHash || null,
        },
      );

      transaction.set(
        rateRef,
        {
          uidHash:
            sha256(uid),

          emailHash:
            sha256(email),

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
// EMAIL LABEL
// ===============================================================

function otpPurposeLabel(purpose) {
  switch (purpose) {
    case 'emailLogin':
      return 'login';

    case 'emailSignUp':
      return 'account verification';

    case 'emailChange':
      return 'email change verification';

    case PASSWORD_RECOVERY_PURPOSE:
      return 'password recovery';

    default:
      return 'verification';
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
}) {
  const purposeLabel =
    otpPurposeLabel(
      purpose,
    );

  const subject =
    purpose ===
    PASSWORD_RECOVERY_PURPOSE
      ? 'Your JR CALL password recovery code'
      : 'Your JR CALL verification code';

  const text = [
    'JR CALL',
    '',
    `Your ${purposeLabel} code is ${otp}.`,
    '',
    'This code expires in 5 minutes.',
    '',
    'If you did not request this code, you can safely ignore this email.',
  ].join('\n');

  const html = `
<!doctype html>
<html>
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
  box-shadow:0 12px 34px rgba(17,24,39,0.06);
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
Secure Email Verification
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
This code expires in
<strong>5 minutes</strong>.
</div>

<div style="
  margin-top:24px;
  padding-top:20px;
  border-top:1px solid #EEF1F5;
  text-align:center;
  color:#8A94A6;
  font-size:12px;
">
If you did not request this code,
you can safely ignore this email.
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
            'JR-CALL-Firebase-Functions/1.0',
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

  let responseData = null;

  try {
    responseData =
      await response.json();
  } catch (_) {
    responseData = null;
  }

  if (!response.ok) {
    console.error(
      'JR CALL Email delivery rejected:',
      {
        status:
          response.status,

        response:
          responseData,
      },
    );

    throw new Error(
      'EMAIL_DELIVERY_FAILED',
    );
  }

  const messageId =
    responseData &&
    typeof responseData.id ===
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
// OTP DELIVERY STATUS
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
  });
}

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
    });
  } catch (error) {
    console.error(
      'JR CALL failed to mark OTP delivery failure:',
      error,
    );
  }
}

// ===============================================================
// EMAIL AVAILABILITY
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
      existingUser.uid !== uid
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
      error &&
      error.code ===
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
// RESOLVE AUTHENTICATED EMAIL OTP TARGET
// ===============================================================

async function resolveAuthenticatedOtpEmail({
  uid,
  requestedEmail,
  purpose,
}) {
  let firebaseUser;

  try {
    firebaseUser =
      await getAuth()
        .getUser(uid);
  } catch (error) {
    console.error(
      'JR CALL failed to load authenticated Firebase user:',
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

  const currentEmail =
    normalizeEmail(
      firebaseUser.email,
    );

  // =============================================================
  // EMAIL LOGIN
  // =============================================================

  if (
    purpose === 'emailLogin'
  ) {
    if (
      currentEmail === '' ||
      currentEmail !== requestedEmail
    ) {
      throw new HttpsError(
        'permission-denied',
        'Requested Email does not match the authenticated Firebase account.',
      );
    }

    const profileSnapshot =
      await db
        .collection(
          USERS_COLLECTION,
        )
        .doc(uid)
        .get();

    if (!profileSnapshot.exists) {
      throw new HttpsError(
        'failed-precondition',
        'This Firebase account does not have an existing JR CALL profile.',
      );
    }

    const profile =
      profileSnapshot.data() || {};

    if (
      profile.isDeleted === true ||
      profile.isBlocked === true
    ) {
      throw new HttpsError(
        'permission-denied',
        'This JR CALL account is unavailable.',
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
      profileEmail !== currentEmail
    ) {
      throw new HttpsError(
        'failed-precondition',
        'JR CALL profile Email does not match Firebase Authentication.',
      );
    }

    return {
      firebaseUser,
      email: currentEmail,
    };
  }

  // =============================================================
  // EMAIL SIGNUP
  // =============================================================

  if (
    purpose === 'emailSignUp'
  ) {
    if (
      currentEmail !== '' &&
      currentEmail !== requestedEmail
    ) {
      throw new HttpsError(
        'failed-precondition',
        'A different Email is already linked to this Firebase account.',
      );
    }

    await ensureEmailAvailableForUid(
      requestedEmail,
      uid,
    );

    return {
      firebaseUser,
      email: requestedEmail,
    };
  }

  // =============================================================
  // EMAIL CHANGE
  // =============================================================

  if (
    purpose === 'emailChange'
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
      firebaseUser,
      email: requestedEmail,
    };
  }

  throw new HttpsError(
    'invalid-argument',
    'Unsupported Email OTP purpose.',
  );
}

// ===============================================================
// SEND AUTHENTICATED EMAIL OTP
// ===============================================================

exports.sendEmailOtp =
  onCall(
    {
      region:
        FUNCTIONS_REGION,

      memory:
        '256MiB',

      timeoutSeconds:
        30,

      maxInstances:
        CALLABLE_MAX_INSTANCES,

      secrets: [
        RESEND_API_KEY,
        EMAIL_OTP_HASH_SECRET,
      ],
    },

    async (request) => {
      const uid =
        requireCallableUid(
          request,
        );

      const data =
        callableData(request);

      const requestedEmail =
        normalizeEmail(
          data.email,
        );

      const purpose =
        normalizePurpose(
          data.purpose,
        );

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
        !AUTHENTICATED_EMAIL_OTP_PURPOSES
          .has(purpose)
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

      const resolved =
        await resolveAuthenticatedOtpEmail({
          uid,
          requestedEmail,
          purpose,
        });

      const email =
        resolved.email;

      const challengeId =
        createChallengeId();

      const otp =
        createSixDigitOtp();

      const otpHash =
        createOtpHash({
          challengeId,
          uid,
          email,
          purpose,
          otp,
          secret:
            hashSecret,
        });

      const reservation =
        await reserveOtpChallenge({
          uid,
          email,
          purpose,
          challengeId,
          otpHash,

          rateCollection:
            EMAIL_OTP_RATE_COLLECTION,

          rateNamespace:
            'authenticated-email-otp',
        });

      try {
        const delivery =
          await sendOtpEmail({
            apiKey:
              resendApiKey,

            from:
              emailFrom,

            email,

            otp,

            purpose,
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
        success: true,

        challengeId,

        expiresIn:
          OTP_EXPIRY_SECONDS,

        resendAfter:
          OTP_RESEND_COOLDOWN_SECONDS,
      };
    },
  );

// ===============================================================
// OTP TRANSACTION VERIFIER
// ===============================================================

async function verifyOtpChallengeTransaction({
  challengeId,
  otp,
  suppliedPurpose,
  hashSecret,
  expectedUid = null,
}) {
  const challengeRef =
    db
      .collection(
        EMAIL_OTP_COLLECTION,
      )
      .doc(
        challengeId,
      );

  return db.runTransaction(
    async (transaction) => {
      const snapshot =
        await transaction.get(
          challengeRef,
        );

      if (!snapshot.exists) {
        throw new HttpsError(
          'not-found',
          'Email OTP challenge was not found.',
        );
      }

      const challenge =
        snapshot.data() || {};

      const challengeUid =
        cleanString(
          challenge.uid,
        );

      const challengeEmail =
        normalizeEmail(
          challenge.email,
        );

      const challengePurpose =
        normalizePurpose(
          challenge.purpose,
        );

      const storedHash =
        cleanString(
          challenge.otpHash,
        );

      const attempts =
        Number.isInteger(
          challenge.attempts,
        )
          ? challenge.attempts
          : 0;

      const maxAttempts =
        Number.isInteger(
          challenge.maxAttempts,
        )
          ? challenge.maxAttempts
          : OTP_MAX_VERIFY_ATTEMPTS;

      const used =
        challenge.used === true;

      const deliveryStatus =
        cleanString(
          challenge.deliveryStatus,
        );

      const expiresAt =
        challenge.expiresAt;

      if (
        challengeUid === ''
      ) {
        throw new HttpsError(
          'failed-precondition',
          'Email OTP challenge owner is invalid.',
        );
      }

      if (
        expectedUid !== null &&
        challengeUid !== expectedUid
      ) {
        throw new HttpsError(
          'permission-denied',
          'This Email OTP challenge does not belong to the authenticated user.',
        );
      }

      if (
        !isValidEmail(
          challengeEmail,
        )
      ) {
        throw new HttpsError(
          'failed-precondition',
          'Email OTP challenge Email is invalid.',
        );
      }

      if (
        challengePurpose !==
        suppliedPurpose
      ) {
        throw new HttpsError(
          'permission-denied',
          'Email OTP purpose does not match the challenge.',
        );
      }

      if (
        deliveryStatus !== 'sent'
      ) {
        throw new HttpsError(
          'failed-precondition',
          'Email OTP was not successfully delivered.',
        );
      }

      if (used) {
        throw new HttpsError(
          'failed-precondition',
          'This Email OTP has already been used.',
        );
      }

      if (
        attempts >= maxAttempts
      ) {
        throw new HttpsError(
          'resource-exhausted',
          'Too many incorrect Email OTP attempts.',
        );
      }

      if (
        !isTimestamp(
          expiresAt,
        )
      ) {
        throw new HttpsError(
          'failed-precondition',
          'Email OTP expiry information is invalid.',
        );
      }

      if (
        expiresAt.toMillis() <=
        Date.now()
      ) {
        transaction.update(
          challengeRef,
          {
            verificationStatus:
              'expired',

            expiredAt:
              FieldValue.serverTimestamp(),
          },
        );

        return {
          status:
            'expired',

          uid:
            challengeUid,

          email:
            challengeEmail,

          purpose:
            challengePurpose,

          attemptsRemaining:
            Math.max(
              maxAttempts -
              attempts,
              0,
            ),
        };
      }

      const suppliedHash =
        createOtpHash({
          challengeId,

          uid:
            challengeUid,

          email:
            challengeEmail,

          purpose:
            challengePurpose,

          otp,

          secret:
            hashSecret,
        });

      const valid =
        timingSafeHashEquals(
          storedHash,
          suppliedHash,
        );

      if (!valid) {
        const nextAttempts =
          attempts + 1;

        const remaining =
          Math.max(
            maxAttempts -
            nextAttempts,
            0,
          );

        transaction.update(
          challengeRef,
          {
            attempts:
              nextAttempts,

            lastAttemptAt:
              FieldValue.serverTimestamp(),

            verificationStatus:
              remaining === 0
                ? 'locked'
                : 'pending',
          },
        );

        return {
          status:
            remaining === 0
              ? 'locked'
              : 'invalid',

          uid:
            challengeUid,

          email:
            challengeEmail,

          purpose:
            challengePurpose,

          attemptsRemaining:
            remaining,
        };
      }

      transaction.update(
        challengeRef,
        {
          used:
            true,

          verificationStatus:
            'verified',

          verifiedAt:
            FieldValue.serverTimestamp(),

          usedAt:
            FieldValue.serverTimestamp(),

          verifiedUid:
            challengeUid,
        },
      );

      return {
        status:
          'verified',

        uid:
          challengeUid,

        email:
          challengeEmail,

        purpose:
          challengePurpose,

        attemptsRemaining:
          Math.max(
            maxAttempts -
            attempts,
            0,
          ),
      };
    },
  );
}

// ===============================================================
// OTP RESULT MAPPING
// ===============================================================

function throwForVerificationStatus(
  result,
) {
  if (
    result.status === 'expired'
  ) {
    throw new HttpsError(
      'deadline-exceeded',
      'Email OTP has expired. Request a new code.',
    );
  }

  if (
    result.status === 'locked'
  ) {
    throw new HttpsError(
      'resource-exhausted',
      'Too many incorrect Email OTP attempts. Request a new code.',
      {
        attemptsRemaining: 0,
      },
    );
  }

  if (
    result.status === 'invalid'
  ) {
    throw new HttpsError(
      'invalid-argument',
      'Email OTP is incorrect.',
      {
        attemptsRemaining:
          result.attemptsRemaining,
      },
    );
  }

  if (
    result.status !== 'verified'
  ) {
    throw new HttpsError(
      'internal',
      'Email OTP verification did not complete.',
    );
  }
}

// ===============================================================
// VERIFY AUTHENTICATED EMAIL OTP
// ===============================================================

exports.verifyEmailOtp =
  onCall(
    {
      region:
        FUNCTIONS_REGION,

      memory:
        '256MiB',

      timeoutSeconds:
        30,

      maxInstances:
        CALLABLE_MAX_INSTANCES,

      secrets: [
        EMAIL_OTP_HASH_SECRET,
      ],
    },

    async (request) => {
      const uid =
        requireCallableUid(
          request,
        );

      const data =
        callableData(request);

      const challengeId =
        normalizeChallengeId(
          data.challengeId,
        );

      const otp =
        normalizeOtp(
          data.otp ??
          data.code,
        );

      const purpose =
        normalizePurpose(
          data.purpose,
        );

      if (
        challengeId === ''
      ) {
        throw new HttpsError(
          'invalid-argument',
          'Email OTP challengeId is required.',
        );
      }

      if (
        !isValidOtp(
          otp,
        )
      ) {
        throw new HttpsError(
          'invalid-argument',
          'A valid 6-digit Email OTP is required.',
        );
      }

      if (
        !AUTHENTICATED_EMAIL_OTP_PURPOSES
          .has(purpose)
      ) {
        throw new HttpsError(
          'invalid-argument',
          'Unsupported Email OTP purpose.',
        );
      }

      const hashSecret =
        EMAIL_OTP_HASH_SECRET
          .value()
          .trim();

      if (
        hashSecret === ''
      ) {
        throw new HttpsError(
          'failed-precondition',
          'Email OTP verification service is not configured.',
        );
      }

      let verificationResult;

      try {
        verificationResult =
          await verifyOtpChallengeTransaction({
            challengeId,

            otp,

            suppliedPurpose:
              purpose,

            hashSecret,

            expectedUid:
              uid,
          });
      } catch (error) {
        if (
          error instanceof HttpsError
        ) {
          throw error;
        }

        console.error(
          'JR CALL Email OTP transaction failed:',
          error,
        );

        throw new HttpsError(
          'internal',
          'Email OTP verification could not be completed.',
        );
      }

      throwForVerificationStatus(
        verificationResult,
      );

      let firebaseUser;

      try {
        firebaseUser =
          await getAuth()
            .getUser(uid);
      } catch (error) {
        console.error(
          'JR CALL Firebase user reload failed:',
          error,
        );

        throw new HttpsError(
          'internal',
          'Email OTP was verified but the Firebase account could not be finalized.',
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

      const currentEmail =
        normalizeEmail(
          firebaseUser.email,
        );

      const verifiedEmail =
        verificationResult.email;

      try {
        // =======================================================
        // EMAIL LOGIN
        // =======================================================

        if (
          purpose === 'emailLogin'
        ) {
          if (
            currentEmail === '' ||
            currentEmail !== verifiedEmail
          ) {
            throw new HttpsError(
              'failed-precondition',
              'Firebase Email changed during OTP verification.',
            );
          }

          if (
            firebaseUser.emailVerified !== true
          ) {
            firebaseUser =
              await getAuth()
                .updateUser(
                  uid,
                  {
                    emailVerified: true,
                  },
                );
          }
        }

        // =======================================================
        // EMAIL SIGNUP / EMAIL CHANGE
        // =======================================================

        else {
          await ensureEmailAvailableForUid(
            verifiedEmail,
            uid,
          );

          firebaseUser =
            await getAuth()
              .updateUser(
                uid,
                {
                  email:
                    verifiedEmail,

                  emailVerified:
                    true,
                },
              );
        }
      } catch (error) {
        if (
          error instanceof HttpsError
        ) {
          throw error;
        }

        console.error(
          'JR CALL Firebase Email finalization failed:',
          error,
        );

        throw new HttpsError(
          'internal',
          'Email OTP was verified but account verification could not be finalized.',
        );
      }

      // =========================================================
      // EXISTING PROFILE SYNC
      // =========================================================
      //
      // Never create an incomplete user profile here.
      //
      // =========================================================

      try {
        const userRef =
          db
            .collection(
              USERS_COLLECTION,
            )
            .doc(uid);

        const snapshot =
          await userRef.get();

        if (snapshot.exists) {
          await userRef.update({
            email:
              verifiedEmail,

            emailNormalized:
              verifiedEmail,

            emailVerified:
              true,

            updatedAt:
              FieldValue.serverTimestamp(),
          });
        }
      } catch (error) {
        console.error(
          'JR CALL Email profile sync skipped:',
          error,
        );
      }

      return {
        success: true,

        verified: true,

        challengeId,

        purpose,

        email:
          verifiedEmail,
      };
    },
  );

// ===============================================================
// PASSWORD RECOVERY OTP — SEND
// ===============================================================
//
// Flutter INPUT:
//
// {
//   email: 'name@example.com'
// }
//
// This does NOT use Firebase Email reset links.
//
// ===============================================================

exports.sendPasswordRecoveryOtp =
  onCall(
    {
      region:
        FUNCTIONS_REGION,

      memory:
        '256MiB',

      timeoutSeconds:
        30,

      maxInstances:
        CALLABLE_MAX_INSTANCES,

      secrets: [
        RESEND_API_KEY,
        EMAIL_OTP_HASH_SECRET,
      ],
    },

    async (request) => {
      const data =
        callableData(request);

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

      const {
        resendApiKey,
        hashSecret,
        emailFrom,
      } =
        requireEmailBackendConfiguration();

      let firebaseUser;

      try {
        firebaseUser =
          await getAuth()
            .getUserByEmail(
              email,
            );
      } catch (error) {
        if (
          error &&
          error.code ===
            'auth/user-not-found'
        ) {
          // Do not reveal account existence.
          return {
            success: true,

            challengeId: null,

            expiresIn:
              OTP_EXPIRY_SECONDS,

            resendAfter:
              OTP_RESEND_COOLDOWN_SECONDS,
          };
        }

        console.error(
          'JR CALL password recovery lookup failed:',
          error,
        );

        throw new HttpsError(
          'unavailable',
          'Password recovery is temporarily unavailable.',
        );
      }

      if (
        firebaseUser.disabled === true
      ) {
        return {
          success: true,

          challengeId: null,

          expiresIn:
            OTP_EXPIRY_SECONDS,

          resendAfter:
            OTP_RESEND_COOLDOWN_SECONDS,
        };
      }

      const providerIds =
        new Set(
          (
            firebaseUser.providerData ||
            []
          ).map(
            (provider) =>
              provider.providerId,
          ),
        );

      if (
        !providerIds.has(
          'password',
        )
      ) {
        return {
          success: true,

          challengeId: null,

          expiresIn:
            OTP_EXPIRY_SECONDS,

          resendAfter:
            OTP_RESEND_COOLDOWN_SECONDS,
        };
      }

      const uid =
        firebaseUser.uid;

      const challengeId =
        createChallengeId();

      const otp =
        createSixDigitOtp();

      const ipHash =
        sha256(
          resolveClientIp(
            request,
          ),
        );

      const otpHash =
        createOtpHash({
          challengeId,

          uid,

          email,

          purpose:
            PASSWORD_RECOVERY_PURPOSE,

          otp,

          secret:
            hashSecret,
        });

      const reservation =
        await reserveOtpChallenge({
          uid,

          email,

          purpose:
            PASSWORD_RECOVERY_PURPOSE,

          challengeId,

          otpHash,

          rateCollection:
            PASSWORD_RECOVERY_RATE_COLLECTION,

          rateNamespace:
            'password-recovery',

          ipHash,
        });

      try {
        const delivery =
          await sendOtpEmail({
            apiKey:
              resendApiKey,

            from:
              emailFrom,

            email,

            otp,

            purpose:
              PASSWORD_RECOVERY_PURPOSE,
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
          'JR CALL password recovery OTP delivery failed:',
          error,
        );

        throw new HttpsError(
          'unavailable',
          'Password recovery code could not be delivered. Please try again.',
        );
      }

      return {
        success: true,

        challengeId,

        expiresIn:
          OTP_EXPIRY_SECONDS,

        resendAfter:
          OTP_RESEND_COOLDOWN_SECONDS,
      };
    },
  );

// ===============================================================
// PASSWORD RECOVERY OTP — VERIFY + RESET PASSWORD
// ===============================================================
//
// Flutter INPUT:
//
// {
//   challengeId: '...',
//   otp: '123456',
//   newPassword: 'new secure password'
// }
//
// Password exists only in request memory long enough to call
// Firebase Admin updateUser().
//
// Password is never written to Firestore.
//
// ===============================================================

exports.verifyPasswordRecoveryOtp =
  onCall(
    {
      region:
        FUNCTIONS_REGION,

      memory:
        '256MiB',

      timeoutSeconds:
        30,

      maxInstances:
        CALLABLE_MAX_INSTANCES,

      secrets: [
        EMAIL_OTP_HASH_SECRET,
      ],
    },

    async (request) => {
      const data =
        callableData(request);

      const challengeId =
        normalizeChallengeId(
          data.challengeId,
        );

      const otp =
        normalizeOtp(
          data.otp ??
          data.code,
        );

      const newPassword =
        typeof data.newPassword ===
          'string'
          ? data.newPassword
          : '';

      if (
        challengeId === ''
      ) {
        throw new HttpsError(
          'invalid-argument',
          'Password recovery challengeId is required.',
        );
      }

      if (
        !isValidOtp(
          otp,
        )
      ) {
        throw new HttpsError(
          'invalid-argument',
          'A valid 6-digit recovery OTP is required.',
        );
      }

      if (
        !isValidPassword(
          newPassword,
        )
      ) {
        throw new HttpsError(
          'invalid-argument',
          'Password must contain at least 6 characters.',
        );
      }

      const hashSecret =
        EMAIL_OTP_HASH_SECRET
          .value()
          .trim();

      if (
        hashSecret === ''
      ) {
        throw new HttpsError(
          'failed-precondition',
          'Password recovery service is not configured.',
        );
      }

      let verificationResult;

      try {
        verificationResult =
          await verifyOtpChallengeTransaction({
            challengeId,

            otp,

            suppliedPurpose:
              PASSWORD_RECOVERY_PURPOSE,

            hashSecret,

            expectedUid:
              null,
          });
      } catch (error) {
        if (
          error instanceof HttpsError
        ) {
          throw error;
        }

        console.error(
          'JR CALL password recovery OTP transaction failed:',
          error,
        );

        throw new HttpsError(
          'internal',
          'Password recovery verification could not be completed.',
        );
      }

      throwForVerificationStatus(
        verificationResult,
      );

      let firebaseUser;

      try {
        firebaseUser =
          await getAuth()
            .getUser(
              verificationResult.uid,
            );
      } catch (error) {
        console.error(
          'JR CALL password recovery user reload failed:',
          error,
        );

        throw new HttpsError(
          'failed-precondition',
          'The account is no longer available.',
        );
      }

      if (
        firebaseUser.disabled === true ||
        normalizeEmail(
          firebaseUser.email,
        ) !== verificationResult.email
      ) {
        throw new HttpsError(
          'failed-precondition',
          'The account changed during password recovery.',
        );
      }

      const providerIds =
        new Set(
          (
            firebaseUser.providerData ||
            []
          ).map(
            (provider) =>
              provider.providerId,
          ),
        );

      if (
        !providerIds.has(
          'password',
        )
      ) {
        throw new HttpsError(
          'failed-precondition',
          'This account does not use Email/Password sign-in.',
        );
      }

      try {
        await getAuth()
          .updateUser(
            firebaseUser.uid,
            {
              password:
                newPassword,
            },
          );
      } catch (error) {
        console.error(
          'JR CALL password update failed:',
          error,
        );

        throw new HttpsError(
          'internal',
          'The new password could not be saved.',
        );
      }

      // =========================================================
      // SECURITY
      // =========================================================
      //
      // Revoke old refresh tokens after password recovery.
      //
      // =========================================================

      try {
        await getAuth()
          .revokeRefreshTokens(
            firebaseUser.uid,
          );
      } catch (error) {
        console.error(
          'JR CALL refresh-token revocation skipped:',
          error,
        );
      }

      return {
        success: true,

        passwordReset: true,
      };
    },
  );

// ===============================================================
// TURN HEADERS
// ===============================================================

function setCorsHeaders(response) {
  response.set(
    'Access-Control-Allow-Origin',
    '*',
  );

  response.set(
    'Access-Control-Allow-Headers',
    'Authorization, Content-Type',
  );

  response.set(
    'Access-Control-Allow-Methods',
    'GET, OPTIONS',
  );

  response.set(
    'Cache-Control',
    'no-store',
  );
}

// ===============================================================
// TURN HOST NORMALIZATION
// ===============================================================

function normalizeTurnHost(value) {
  if (
    typeof value !== 'string'
  ) {
    return '';
  }

  let normalized =
    value.trim();

  if (
    normalized === ''
  ) {
    return '';
  }

  normalized =
    normalized.replace(
      /^turns?:\/\//i,
      '',
    );

  normalized =
    normalized
      .split('/')[0]
      .split('?')[0]
      .trim();

  if (
    normalized.startsWith('[')
  ) {
    const closeIndex =
      normalized.indexOf(']');

    return closeIndex > 0
      ? normalized.substring(
          0,
          closeIndex + 1,
        )
      : '';
  }

  const colonIndex =
    normalized.indexOf(':');

  if (
    colonIndex > 0 &&
    normalized.indexOf(
      ':',
      colonIndex + 1,
    ) === -1
  ) {
    normalized =
      normalized.substring(
        0,
        colonIndex,
      );
  }

  return normalized.trim();
}

// ===============================================================
// TURN TTL
// ===============================================================

function resolveTurnTtl(value) {
  const parsed =
    Number.parseInt(
      String(value),
      10,
    );

  if (
    !Number.isFinite(
      parsed,
    )
  ) {
    return 3600;
  }

  return Math.min(
    Math.max(
      parsed,
      300,
    ),
    86400,
  );
}

// ===============================================================
// TURN AUTH
// ===============================================================

async function authenticateTurnRequest(
  request,
) {
  const authorization =
    request &&
    request.headers
      ? request.headers.authorization ||
        ''
      : '';

  if (
    typeof authorization !== 'string' ||
    !authorization.startsWith(
      'Bearer ',
    )
  ) {
    throw new Error(
      'AUTHORIZATION_REQUIRED',
    );
  }

  const idToken =
    authorization
      .substring(7)
      .trim();

  if (
    idToken === ''
  ) {
    throw new Error(
      'AUTHORIZATION_REQUIRED',
    );
  }

  return getAuth()
    .verifyIdToken(
      idToken,
      true,
    );
}

// ===============================================================
// TURN TEMPORARY CREDENTIAL
// ===============================================================

function createTurnCredential({
  uid,
  ttlSeconds,
  sharedSecret,
}) {
  const expiresAt =
    Math.floor(
      Date.now() / 1000,
    ) +
    ttlSeconds;

  const safeUid =
    String(uid)
      .replace(
        /[^a-zA-Z0-9_-]/g,
        '',
      )
      .substring(
        0,
        64,
      );

  if (
    safeUid === ''
  ) {
    throw new Error(
      'INVALID_UID',
    );
  }

  const username =
    `${expiresAt}:${safeUid}`;

  const credential =
    crypto
      .createHmac(
        'sha1',
        sharedSecret,
      )
      .update(
        username,
      )
      .digest(
        'base64',
      );

  return {
    username,
    credential,
    expiresAt,
  };
}

// ===============================================================
// TURN URLS
// ===============================================================

function buildTurnUrls(host) {
  if (
    typeof host !== 'string' ||
    host.trim() === ''
  ) {
    return [];
  }

  const normalizedHost =
    host.trim();

  return [
    `turn:${normalizedHost}:3478?transport=udp`,
    `turn:${normalizedHost}:3478?transport=tcp`,
    `turns:${normalizedHost}:5349?transport=tcp`,
  ];
}

// ===============================================================
// TURN CREDENTIAL ENDPOINT
// ===============================================================

exports.getTurnCredentials =
  onRequest(
    {
      region:
        FUNCTIONS_REGION,

      memory:
        '256MiB',

      timeoutSeconds:
        15,

      maxInstances:
        TURN_MAX_INSTANCES,

      secrets: [
        TURN_SHARED_SECRET,
      ],
    },

    async (
      request,
      response,
    ) => {
      setCorsHeaders(
        response,
      );

      if (
        request.method === 'OPTIONS'
      ) {
        response
          .status(204)
          .send('');

        return;
      }

      if (
        request.method !== 'GET'
      ) {
        response
          .status(405)
          .json({
            success: false,

            error:
              'METHOD_NOT_ALLOWED',
          });

        return;
      }

      try {
        const decodedToken =
          await authenticateTurnRequest(
            request,
          );

        const uid =
          cleanString(
            decodedToken.uid,
          );

        if (
          uid === ''
        ) {
          response
            .status(401)
            .json({
              success: false,

              error:
                'INVALID_AUTHENTICATION',
            });

          return;
        }

        const sharedSecret =
          TURN_SHARED_SECRET
            .value()
            .trim();

        const primaryHost =
          normalizeTurnHost(
            TURN_PRIMARY_HOST
              .value(),
          );

        const backupHost =
          normalizeTurnHost(
            TURN_BACKUP_HOST
              .value(),
          );

        // =======================================================
        // TURN IS OPTIONAL FOR AUTHENTICATION
        // =======================================================
        //
        // TURN absence must never block:
        // - Login
        // - Signup
        // - Phone OTP
        // - Email OTP
        // - Profile
        //
        // Flutter Call Engine may use STUN fallback.
        //
        // =======================================================

        if (
          sharedSecret === '' ||
          primaryHost === ''
        ) {
          console.warn(
            'JR CALL TURN backend is not configured; client will use STUN fallback.',
          );

          response
            .status(503)
            .json({
              success: false,

              error:
                'TURN_NOT_CONFIGURED',
            });

          return;
        }

        const ttlSeconds =
          resolveTurnTtl(
            TURN_TTL_SECONDS
              .value(),
          );

        const {
          username,
          credential,
          expiresAt,
        } =
          createTurnCredential({
            uid,

            ttlSeconds,

            sharedSecret,
          });

        const iceServers = [];

        const primaryUrls =
          buildTurnUrls(
            primaryHost,
          );

        if (
          primaryUrls.length > 0
        ) {
          iceServers.push({
            urls:
              primaryUrls,

            username,

            credential,
          });
        }

        if (
          backupHost !== '' &&
          backupHost !== primaryHost
        ) {
          const backupUrls =
            buildTurnUrls(
              backupHost,
            );

          if (
            backupUrls.length > 0
          ) {
            iceServers.push({
              urls:
                backupUrls,

              username,

              credential,
            });
          }
        }

        if (
          iceServers.length === 0
        ) {
          response
            .status(503)
            .json({
              success: false,

              error:
                'TURN_NOT_CONFIGURED',
            });

          return;
        }

        const requestedRegion =
          request.query &&
          typeof request.query.region ===
            'string'
            ? request.query.region
                .trim()
                .substring(
                  0,
                  64,
                )
            : '';

        response
          .status(200)
          .json({
            success: true,

            region:
              requestedRegion ||
              'global',

            expiresIn:
              ttlSeconds,

            expiresAt,

            iceServers,
          });
      } catch (error) {
        if (
          error instanceof Error &&
          error.message ===
            'AUTHORIZATION_REQUIRED'
        ) {
          response
            .status(401)
            .json({
              success: false,

              error:
                'AUTHORIZATION_REQUIRED',
            });

          return;
        }

        if (
          error instanceof Error &&
          error.message ===
            'INVALID_UID'
        ) {
          response
            .status(401)
            .json({
              success: false,

              error:
                'INVALID_AUTHENTICATION',
            });

          return;
        }

        console.error(
          'JR CALL getTurnCredentials failure:',
          error,
        );

        response
          .status(401)
          .json({
            success: false,

            error:
              'INVALID_AUTHENTICATION',
          });
      }
    },
  );

// ===============================================================
// END OF FILE
// ===============================================================
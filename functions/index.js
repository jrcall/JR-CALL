'use strict';

const { getMessaging } = require('firebase-admin/messaging');

const { onDocumentUpdated } = require('firebase-functions/v2/firestore');

// ===============================================================
// JR CALL
// File: index.js
// Location: functions/index.js
//
// OTP / AUTH MASTER FILE 09 / 09
// MAIN CLOUD FUNCTIONS ENTRY
//
// ===============================================================
//
// CURRENT JR CALL AUTH CONTRACT:
//
// ACCOUNT CREATION:
//
// ✓ Firebase-verified Phone Number is mandatory.
// ✓ Account cannot be completed without Phone verification.
// ✓ All other optional profile fields may be skipped.
// ✓ Email is optional.
// ✓ If Email credential is added, Password belongs to the same UID.
//
// PHONE:
//
// ✓ Phone Signup requires Firebase Phone OTP.
// ✓ Phone Login requires Firebase Phone OTP.
// ✓ Phone OTP is Firebase Authentication-owned.
// ✓ This backend NEVER generates Phone OTP.
// ✓ This backend NEVER verifies Phone OTP.
// ✓ No custom Phone OTP.
// ✓ No fake/local Phone OTP.
// ✓ No Phone password authentication backend.
//
// EMAIL LOGIN:
//
// ✓ Email + Password Login is direct Firebase Authentication.
// ✓ Normal Email Login requires NO Email OTP.
// ✓ Normal Email Login requires NO Email verification gate here.
// ✓ Existing Email OTP callable remains compatibility-only.
//
// PASSWORD RECOVERY:
//
// ✓ Existing Email recovery OTP preserved.
// ✓ OTP verification + password reset preserved.
// ✓ Refresh-token revocation remains recovery-only.
//
// MULTI-DEVICE:
//
// ✓ Normal Login does not revoke other sessions here.
// ✓ Same Firebase account can remain authenticated on multiple
//   supported devices subject to Firebase client/session behavior.
//
// OTP BACKEND SPLIT:
//
// managers/otp_manager.js
//   -> sendEmailOtpHandler
//
// managers/otp_manager_part2.js
//   -> verifyEmailOtpHandler
//   -> sendPasswordRecoveryOtpHandler
//   -> verifyPasswordRecoveryOtpHandler
//
// PROTECTED:
//
// ✓ Call Engine untouched.
// ✓ WebRTC untouched.
// ✓ Signaling untouched.
// ✓ Message Engine untouched.
// ===============================================================

const crypto = require('crypto');

const {
  initializeApp,
} = require('firebase-admin/app');

const {
  getAuth,
} = require('firebase-admin/auth');

const {
  getFirestore,
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
// FIREBASE INITIALIZATION
// ===============================================================

initializeApp();

const db =
  getFirestore();

// ===============================================================
// OTP MANAGER — PART 1
// ===============================================================

const {
  sendEmailOtpHandler,
} = require(
  './managers/otp_manager',
);

// ===============================================================
// OTP MANAGER — PART 2
// ===============================================================

const {
  verifyEmailOtpHandler,
  sendPasswordRecoveryOtpHandler,
  verifyPasswordRecoveryOtpHandler,
} = require(
  './managers/otp_manager_part2',
);

// ===============================================================
// FUNCTION-BOUND SECRETS
//
// Firebase 2nd-gen secrets must be explicitly bound to every
// function that requires runtime access.
// ===============================================================

const RESEND_API_KEY =
  defineSecret(
    'RESEND_API_KEY',
  );

const EMAIL_OTP_HASH_SECRET =
  defineSecret(
    'EMAIL_OTP_HASH_SECRET',
  );

// ===============================================================
// REGION / RESOURCE POLICY
// ===============================================================

const FUNCTIONS_REGION =
  'us-central1';

const CALLABLE_MAX_INSTANCES =
  10;

const TURN_MAX_INSTANCES =
  5;

// ===============================================================
// COLLECTIONS
// ===============================================================

const USERS_COLLECTION =
  'users';

const PHONE_LOOKUP_RATE_COLLECTION =
  'phone_lookup_rate_limits';

// ===============================================================
// PHONE LOOKUP POLICY
//
// Compatibility-only endpoint.
//
// IMPORTANT:
//
// Phone Signup/Login MUST use Firebase Authentication Phone
// verification as the authoritative authentication operation.
//
// This lookup:
//
// ✓ Does NOT send SMS.
// ✓ Does NOT verify OTP.
// ✓ Does NOT authenticate a user.
// ✓ Does NOT create an account.
// ✓ Must never replace Firebase Phone verification.
// ===============================================================

const PHONE_LOOKUP_WINDOW_SECONDS =
  10 * 60;

const PHONE_LOOKUP_MAX_REQUESTS =
  30;

// ===============================================================
// TURN CONFIG
// ===============================================================

const TURN_SHARED_SECRET =
  defineSecret(
    'TURN_SHARED_SECRET',
  );

const TURN_PRIMARY_HOST =
  defineString(
    'TURN_PRIMARY_HOST',
    {
      default:
        '',
    },
  );

const TURN_BACKUP_HOST =
  defineString(
    'TURN_BACKUP_HOST',
    {
      default:
        '',
    },
  );

const TURN_TTL_SECONDS =
  defineString(
    'TURN_TTL_SECONDS',
    {
      default:
        '3600',
    },
  );

// ===============================================================
// BASIC HELPERS
// ===============================================================

function cleanString(value) {
  return typeof value === 'string'
    ? value.trim()
    : '';
}

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
// PHONE NORMALIZATION
// ===============================================================

function normalizePhoneNumber(value) {
  if (
    typeof value !== 'string'
  ) {
    return '';
  }

  return value
    .trim()
    .replace(
      /[\s()\-.]/g,
      '',
    );
}

function normalizePhoneForSearch(value) {
  const phone =
    normalizePhoneNumber(
      value,
    );

  if (
    phone === ''
  ) {
    return '';
  }

  if (
    !phone.startsWith('+')
  ) {
    return phone.replace(
      /[^0-9]/g,
      '',
    );
  }

  const digits =
    phone
      .substring(1)
      .replace(
        /[^0-9]/g,
        '',
      );

  return digits === ''
    ? ''
    : `+${digits}`;
}

function isValidE164Phone(value) {
  return /^\+[1-9][0-9]{7,14}$/.test(
    value,
  );
}

// ===============================================================
// TIMESTAMP
// ===============================================================

function timestampToMillis(value) {
  return value instanceof Timestamp
    ? value.toMillis()
    : 0;
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

  if (
    forwarded !== ''
  ) {
    return forwarded
      .split(',')[0]
      .trim()
      .substring(
        0,
        128,
      );
  }

  const requestIp =
    typeof rawRequest.ip ===
      'string'
      ? rawRequest.ip.trim()
      : '';

  return requestIp === ''
    ? 'unknown'
    : requestIp.substring(
        0,
        128,
      );
}

// ===============================================================
// PHONE LOOKUP RATE LIMIT
// ===============================================================

async function enforcePhoneLookupRateLimit(
  request,
) {
  const ipHash =
    sha256(
      resolveClientIp(
        request,
      ),
    );

  const ref =
    db
      .collection(
        PHONE_LOOKUP_RATE_COLLECTION,
      )
      .doc(
        ipHash,
      );

  const now =
    Timestamp.now();

  await db.runTransaction(
    async (transaction) => {
      const snapshot =
        await transaction.get(
          ref,
        );

      let count =
        0;

      let windowStartedAt =
        now;

      if (
        snapshot.exists
      ) {
        const data =
          snapshot.data() ||
          {};

        const storedCount =
          Number.isInteger(
            data.count,
          )
            ? Math.max(
                data.count,
                0,
              )
            : 0;

        const startMillis =
          timestampToMillis(
            data.windowStartedAt,
          );

        const expired =
          startMillis === 0 ||
          now.toMillis() -
              startMillis >=
            PHONE_LOOKUP_WINDOW_SECONDS *
              1000;

        if (!expired) {
          count =
            storedCount;

          if (
            data.windowStartedAt instanceof
            Timestamp
          ) {
            windowStartedAt =
              data.windowStartedAt;
          }
        }
      }

      if (
        count >=
        PHONE_LOOKUP_MAX_REQUESTS
      ) {
        throw new HttpsError(
          'resource-exhausted',
          'Too many requests. Please try again later.',
        );
      }

      transaction.set(
        ref,
        {
          ipHash,

          count:
            count + 1,

          windowStartedAt,

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
}

// ===============================================================
// PHONE ACCOUNT LOOKUP
//
// COMPATIBILITY-ONLY.
//
// AUTHORITATIVE PHONE FLOW:
//
// Flutter / supported Firebase client
//
//   -> Firebase Phone Authentication
//   -> SMS verification
//   -> Phone credential
//   -> Firebase Authentication session
//   -> JR CALL profile/account logic
//
// This callable:
//
// ✓ Does not send OTP.
// ✓ Does not verify OTP.
// ✓ Does not authenticate.
// ✓ Does not bypass Phone verification.
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
        callableData(
          request,
        );

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
          error?.code ===
          'auth/user-not-found'
        ) {
          return {
            exists:
              false,
          };
        }

        console.error(
          'JR CALL Phone account lookup failed:',
          error,
        );

        throw new HttpsError(
          'unavailable',
          'Phone account verification is temporarily unavailable.',
        );
      }

      const uid =
        cleanString(
          firebaseUser?.uid,
        );

      if (
        uid === ''
      ) {
        return {
          exists:
            false,
        };
      }

      const authPhone =
        normalizePhoneForSearch(
          firebaseUser.phoneNumber ||
          '',
        );

      const requestedPhone =
        normalizePhoneForSearch(
          phoneNumber,
        );

      if (
        authPhone === '' ||
        authPhone !==
          requestedPhone
      ) {
        return {
          exists:
            false,
        };
      }

      let snapshot;

      try {
        snapshot =
          await db
            .collection(
              USERS_COLLECTION,
            )
            .doc(
              uid,
            )
            .get();
      } catch (error) {
        console.error(
          'JR CALL Phone profile lookup failed:',
          error,
        );

        throw new HttpsError(
          'unavailable',
          'Phone account verification is temporarily unavailable.',
        );
      }

      if (
        !snapshot.exists
      ) {
        return {
          exists:
            false,
        };
      }

      const profile =
        snapshot.data() ||
        {};

      if (
        profile.isDeleted === true ||
        profile.isBlocked === true
      ) {
        return {
          exists:
            false,
        };
      }

      const storedPhone =
        normalizePhoneForSearch(
          profile.phoneNormalized ||
          profile.phoneNumber ||
          profile.phone ||
          '',
        );

      if (
        storedPhone !== '' &&
        storedPhone !==
          requestedPhone
      ) {
        return {
          exists:
            false,
        };
      }

      return {
        exists:
          true,
      };
    },
  );

// ===============================================================
// EMAIL OTP — SEND
//
// PART 1
//
// IMPORTANT:
//
// Normal Email + Password Login does NOT require this callable.
//
// This callable remains for supported Email OTP operations and
// compatibility with the existing OTP manager contract.
//
// REQUIRED SECRETS:
//
// RESEND_API_KEY
// EMAIL_OTP_HASH_SECRET
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
      return sendEmailOtpHandler(
        request,
      );
    },
  );

// ===============================================================
// EMAIL OTP — VERIFY
//
// PART 2
//
// IMPORTANT:
//
// Normal Email + Password Login does NOT require Email OTP.
//
// emailLogin OTP support remains compatibility-only inside the
// manager so older/transitional callers are not broken.
//
// REQUIRED SECRET:
//
// EMAIL_OTP_HASH_SECRET
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
      return verifyEmailOtpHandler(
        request,
      );
    },
  );

// ===============================================================
// PASSWORD RECOVERY OTP — SEND
//
// PART 2
//
// Existing recovery behavior is preserved.
//
// REQUIRED SECRETS:
//
// RESEND_API_KEY
// EMAIL_OTP_HASH_SECRET
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
      return sendPasswordRecoveryOtpHandler(
        request,
      );
    },
  );

// ===============================================================
// PASSWORD RECOVERY OTP — VERIFY
//
// PART 2
//
// ✓ OTP verification remains server-owned.
// ✓ New password exists only in request memory.
// ✓ Firebase Admin performs password update.
// ✓ Successful password recovery may revoke refresh tokens.
//
// REQUIRED SECRET:
//
// EMAIL_OTP_HASH_SECRET
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
      return verifyPasswordRecoveryOtpHandler(
        request,
      );
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
    normalized.startsWith(
      '[',
    )
  ) {
    const closeIndex =
      normalized.indexOf(
        ']',
      );

    return closeIndex > 0
      ? normalized.substring(
          0,
          closeIndex + 1,
        )
      : '';
  }

  const colonIndex =
    normalized.indexOf(
      ':',
    );

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
// TURN AUTHENTICATION
// ===============================================================

async function authenticateTurnRequest(
  request,
) {
  const authorization =
    typeof request?.headers
      ?.authorization ===
      'string'
      ? request.headers
          .authorization
      : '';

  if (
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
      Date.now() /
        1000,
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
//
// PROTECTED CALL INFRASTRUCTURE.
//
// Existing behavior is preserved.
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
        request.method ===
        'OPTIONS'
      ) {
        response
          .status(204)
          .send('');

        return;
      }

      if (
        request.method !==
        'GET'
      ) {
        response
          .status(405)
          .json({
            success:
              false,

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
              success:
                false,

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

        if (
          sharedSecret === '' ||
          primaryHost === ''
        ) {
          console.warn(
            'JR CALL TURN is not configured; client may use STUN fallback.',
          );

          response
            .status(503)
            .json({
              success:
                false,

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

        const iceServers =
          [];

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
          backupHost !==
            primaryHost
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
              success:
                false,

              error:
                'TURN_NOT_CONFIGURED',
            });

          return;
        }

        const requestedRegion =
          typeof request.query
            ?.region === 'string'
            ? request.query
                .region
                .trim()
                .substring(
                  0,
                  64,
                )
            : '';

        response
          .status(200)
          .json({
            success:
              true,

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
              success:
                false,

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
              success:
                false,

              error:
                'INVALID_AUTHENTICATION',
            });

          return;
        }

        console.error(
          'JR CALL TURN credential failure:',
          error,
        );

        response
          .status(401)
          .json({
            success:
              false,

            error:
              'INVALID_AUTHENTICATION',
          });
      }
    },
  );

// ===============================================================
// END OF FILE
//
// OTP / AUTH MASTER FILE 09 / 09
//
// BACKEND MODULE CONTRACT:
//
// ✓ otp_manager.js preserved.
// ✓ otp_manager_part2.js preserved.
// ✓ sendEmailOtp callable preserved.
// ✓ verifyEmailOtp callable preserved.
// ✓ sendPasswordRecoveryOtp callable preserved.
// ✓ verifyPasswordRecoveryOtp callable preserved.
// ✓ checkPhoneAccountExists callable preserved.
// ✓ getTurnCredentials endpoint preserved.
//
// PHONE:
//
// ✓ Phone Number remains mandatory account identity by client flow.
// ✓ Phone Signup must use Firebase Phone OTP.
// ✓ Phone Login must use Firebase Phone OTP.
// ✓ Phone OTP remains Firebase Authentication-owned.
// ✓ Backend does not generate Phone SMS OTP.
// ✓ Backend does not verify Phone SMS OTP.
// ✓ No fake/local Phone OTP.
// ✓ No custom Phone OTP database.
// ✓ Phone lookup is compatibility-only.
// ✓ Phone lookup cannot authenticate.
// ✓ Phone lookup cannot bypass OTP.
//
// EMAIL:
//
// ✓ Email remains optional account credential.
// ✓ Normal Email + Password Login requires NO Email OTP.
// ✓ Normal Email Login requires NO Email verification gate here.
// ✓ Legacy Email OTP callable compatibility preserved.
// ✓ Email credential remains attached to canonical Firebase UID.
//
// PASSWORD RECOVERY:
//
// ✓ Recovery OTP send preserved.
// ✓ Recovery OTP verification preserved.
// ✓ Firebase Admin password reset preserved.
// ✓ Raw password never persisted here.
// ✓ Recovery refresh-token revocation remains manager-owned.
//
// MULTI-DEVICE:
//
// ✓ Normal Login does not revoke sessions in this entry file.
// ✓ No single-device restriction introduced.
//
// FIREBASE:
//
// ✓ Firebase UID remains canonical.
// ✓ Firebase Admin initialization preserved.
// ✓ Firebase 2nd-gen functions preserved.
// ✓ us-central1 preserved.
// ✓ Required secrets explicitly bound.
// ✓ Existing callable names preserved.
//
// SECURITY:
//
// ✓ RESEND_API_KEY remains server-side.
// ✓ EMAIL_OTP_HASH_SECRET remains server-side.
// ✓ TURN_SHARED_SECRET remains server-side.
// ✓ Phone lookup remains rate-limited.
// ✓ TURN authentication remains Firebase ID-token protected.
//
// PROTECTED:
//
// ✓ Call Engine untouched.
// ✓ WebRTC untouched.
// ✓ Signaling untouched.
// ✓ Message Engine untouched.
//
// SAVE:
//
// functions/index.js
// ===============================================================


// ===============================================================
// INCOMING CALL PUSH DELIVERY
//
// Firestore call document is created first, then the initial
// WebRTC offer is published.
//
// The push is therefore sent only when offerRevision changes
// from 0 -> 1. This prevents waking the receiver before the
// initial SDP offer is actually available.
//
// Android receives a DATA-ONLY high-priority FCM message.
// Existing JR CALL ownership remains:
//
// FCM
//   -> main.dart background/foreground messaging handler
//   -> BackgroundCallService
//   -> MainActivity.showIncomingCall
//   -> ringtone / call notification / full-screen presentation
//
// No WebRTC / ICE / signaling ownership is moved here.
// ===============================================================

function jrCallPushString(value) {
  if (typeof value !== 'string') {
    return '';
  }

  return value.trim();
}

function jrCallPushProfileName(data) {
  if (!data || typeof data !== 'object') {
    return '';
  }

  return (
    jrCallPushString(data.name) ||
    jrCallPushString(data.fullName) ||
    jrCallPushString(data.displayName)
  );
}

function jrCallPushProfilePhoto(data) {
  if (!data || typeof data !== 'object') {
    return '';
  }

  return (
    jrCallPushString(data.photoUrl) ||
    jrCallPushString(data.profilePhotoUrl)
  );
}

exports.sendIncomingCallNotification =
  onDocumentUpdated(
    {
      document:
        'calls/{callId}',

      region:
        FUNCTIONS_REGION,

      memory:
        '256MiB',

      timeoutSeconds:
        30,
    },
    async (event) => {
      const change =
        event.data;

      if (!change) {
        return;
      }

      const before =
        change.before.data() || {};

      const after =
        change.after.data() || {};

      const callId =
        jrCallPushString(
          event.params?.callId,
        );

      if (!callId) {
        return;
      }

      const beforeOfferRevision =
        Number.isInteger(
          before.offerRevision,
        )
          ? before.offerRevision
          : 0;

      const afterOfferRevision =
        Number.isInteger(
          after.offerRevision,
        )
          ? after.offerRevision
          : 0;

      // Initial SDP offer only.
      //
      // ICE-restart offers use later revisions and must never
      // create another incoming-call notification.
      if (
        beforeOfferRevision !== 0 ||
        afterOfferRevision !== 1
      ) {
        return;
      }

      const offer =
        after.offer;

      if (
        !offer ||
        typeof offer !== 'object' ||
        Array.isArray(offer) ||
        jrCallPushString(
          offer.type,
        ).toLowerCase() !== 'offer' ||
        !jrCallPushString(
          offer.sdp,
        )
      ) {
        console.warn(
          `[JR CALL][FCM] Initial offer is invalid for call ${callId}.`,
        );

        return;
      }

      const callerId =
        jrCallPushString(
          after.callerId,
        );

      const receiverId =
        jrCallPushString(
          after.receiverId,
        );

      if (
        !callerId ||
        !receiverId ||
        callerId === receiverId
      ) {
        console.warn(
          `[JR CALL][FCM] Invalid participants for call ${callId}.`,
        );

        return;
      }

      // Read latest call state before waking the receiver.
      // Do not surface an already-ended/cancelled call.
      const latestCallSnapshot =
        await change.after.ref.get();

      if (!latestCallSnapshot.exists) {
        return;
      }

      const latestCall =
        latestCallSnapshot.data() || {};

      const latestStatus =
        jrCallPushString(
          latestCall.status,
        ).toLowerCase();

      if (
        latestStatus !== 'calling' &&
        latestStatus !== 'ringing'
      ) {
        return;
      }

      const receiverRef =
        db.collection('users')
          .doc(receiverId);

      const callerRef =
        db.collection('users')
          .doc(callerId);

      const [
        receiverSnapshot,
        callerSnapshot,
      ] = await Promise.all([
        receiverRef.get(),
        callerRef.get(),
      ]);

      if (!receiverSnapshot.exists) {
        console.warn(
          `[JR CALL][FCM] Receiver profile is missing for call ${callId}.`,
        );

        return;
      }

      const receiver =
        receiverSnapshot.data() || {};

      const token =
        jrCallPushString(
          receiver.deviceToken,
        ) ||
        jrCallPushString(
          receiver.fcmToken,
        );

      const dispatchRef =
        db.collection(
          'call_push_dispatches',
        ).doc(callId);

      if (!token) {
        // JR_CALL_RINGING_AFTER_PUSH
        try {
          const callRef =
            db.collection('calls').doc(callId);

          await db.runTransaction(
            async (transaction) => {
              const snapshot =
                await transaction.get(callRef);

              if (!snapshot.exists) {
                return;
              }

              const current =
                snapshot.data() || {};

              const currentStatus =
                jrCallPushString(
                  current.status,
                ).toLowerCase();

              if (
                currentStatus !== 'calling'
              ) {
                return;
              }

              transaction.update(
                callRef,
                {
                  status:
                    'ringing',

                  ringingAt:
                    Timestamp.now(),

                  updatedAt:
                    Timestamp.now(),
                },
              );
            },
          );
        } catch (ringingError) {
          console.error(
            `[JR CALL][FCM] Ringing acknowledgement failed. call=${callId}`,
            ringingError,
          );
        }

        await dispatchRef.set(
          {
            callId,
            receiverId,
            state:
              'no_token',
            completedAt:
              Timestamp.now(),
          },
          {
            merge: true,
          },
        );

        console.warn(
          `[JR CALL][FCM] Receiver has no device token for call ${callId}.`,
        );

        return;
      }

      // ---------------------------------------------------------
      // IDEMPOTENT DELIVERY LEASE
      //
      // Firestore events can occasionally be delivered more than
      // once. The short lease prevents duplicate ringing while
      // still allowing another invocation after an interrupted
      // dispatch.
      // ---------------------------------------------------------

      let claimed =
        false;

      await db.runTransaction(
        async (transaction) => {
          const dispatchSnapshot =
            await transaction.get(
              dispatchRef,
            );

          const dispatch =
            dispatchSnapshot.exists
              ? dispatchSnapshot.data() || {}
              : {};

          if (
            dispatch.state === 'sent'
          ) {
            return;
          }

          const leaseUntilMillis =
            dispatch.leaseUntil &&
            typeof dispatch.leaseUntil.toMillis === 'function'
              ? dispatch.leaseUntil.toMillis()
              : 0;

          const now =
            Date.now();

          if (
            dispatch.state === 'sending' &&
            leaseUntilMillis > now
          ) {
            return;
          }

          transaction.set(
            dispatchRef,
            {
              callId,
              callerId,
              receiverId,

              state:
                'sending',

              eventId:
                jrCallPushString(
                  event.id,
                ),

              startedAt:
                Timestamp.now(),

              leaseUntil:
                Timestamp.fromMillis(
                  now + 15000,
                ),
            },
            {
              merge: true,
            },
          );

          claimed =
            true;
        },
      );

      if (!claimed) {
        return;
      }

      const caller =
        callerSnapshot.exists
          ? callerSnapshot.data() || {}
          : {};

      const callerName =
        jrCallPushString(
          latestCall.callerName,
        ) ||
        jrCallPushProfileName(
          caller,
        ) ||
        'JR CALL User';

      const callerPhoto =
        jrCallPushString(
          latestCall.callerPhoto,
        ) ||
        jrCallPushProfilePhoto(
          caller,
        );

      const isVideoCall =
        latestCall.isVideoCall === true ||
        latestCall.video === true;

      try {
        const messageId =
          await getMessaging().send(
            {
              token,

              // DATA-ONLY payload:
              // JR CALL already owns notification/full-screen UI.
              data: {
                type:
                  'incoming_call',

                event:
                  'incoming_call',

                action:
                  'incoming_call',

                notificationType:
                  'incoming_call',

                callId,

                callerId,

                receiverId,

                callerName,

                callerPhoto,

                callerPhotoUrl:
                  callerPhoto,

                isVideoCall:
                  isVideoCall
                    ? 'true'
                    : 'false',

                video:
                  isVideoCall
                    ? 'true'
                    : 'false',

                callType:
                  isVideoCall
                    ? 'video'
                    : 'voice',

                sentAt:
                  String(
                    Date.now(),
                  ),
              },

              android: {
                priority:
                  'high',

                ttl:
                  45000,
              },
            },
          );

        // JR_CALL_RINGING_AFTER_PUSH
        try {
          const callRef =
            db.collection('calls').doc(callId);

          await db.runTransaction(
            async (transaction) => {
              const snapshot =
                await transaction.get(callRef);

              if (!snapshot.exists) {
                return;
              }

              const current =
                snapshot.data() || {};

              const currentStatus =
                jrCallPushString(
                  current.status,
                ).toLowerCase();

              if (
                currentStatus !== 'calling'
              ) {
                return;
              }

              transaction.update(
                callRef,
                {
                  status:
                    'ringing',

                  ringingAt:
                    Timestamp.now(),

                  updatedAt:
                    Timestamp.now(),
                },
              );
            },
          );
        } catch (ringingError) {
          console.error(
            `[JR CALL][FCM] Ringing acknowledgement failed. call=${callId}`,
            ringingError,
          );
        }

        await dispatchRef.set(
          {
            state:
              'sent',

            messageId,

            sentAt:
              Timestamp.now(),

            leaseUntil:
              Timestamp.fromMillis(0),
          },
          {
            merge: true,
          },
        );

        console.log(
          `[JR CALL][FCM] Incoming call push sent. call=${callId} receiver=${receiverId}`,
        );
      } catch (error) {
        const errorCode =
          jrCallPushString(
            error?.code,
          );

        const errorMessage =
          jrCallPushString(
            error?.message,
          ).slice(
            0,
            500,
          );

        // JR_CALL_RINGING_AFTER_PUSH
        try {
          const callRef =
            db.collection('calls').doc(callId);

          await db.runTransaction(
            async (transaction) => {
              const snapshot =
                await transaction.get(callRef);

              if (!snapshot.exists) {
                return;
              }

              const current =
                snapshot.data() || {};

              const currentStatus =
                jrCallPushString(
                  current.status,
                ).toLowerCase();

              if (
                currentStatus !== 'calling'
              ) {
                return;
              }

              transaction.update(
                callRef,
                {
                  status:
                    'ringing',

                  ringingAt:
                    Timestamp.now(),

                  updatedAt:
                    Timestamp.now(),
                },
              );
            },
          );
        } catch (ringingError) {
          console.error(
            `[JR CALL][FCM] Ringing acknowledgement failed. call=${callId}`,
            ringingError,
          );
        }

        await dispatchRef.set(
          {
            state:
              'failed',

            errorCode,

            errorMessage,

            failedAt:
              Timestamp.now(),

            leaseUntil:
              Timestamp.fromMillis(0),
          },
          {
            merge: true,
          },
        );

        console.error(
          `[JR CALL][FCM] Incoming call push failed. call=${callId} code=${errorCode || 'unknown'}`,
        );

        throw error;
      }
    },
  );

// ===============================================================
// END INCOMING CALL PUSH DELIVERY
// ===============================================================

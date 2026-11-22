<!--
Source: https://developer.apple.com/documentation/signinwithapplerestapi/revoke-tokens
Final URL: https://developer.apple.com/tutorials/data/documentation/signinwithapplerestapi/revoke-tokens.json
Retrieved (UTC): 2026-11-22T04:11:57Z
Raw file: siwa-rest-revoke-tokens.json
SHA-256 of raw: 127e58869c8e12927ab705efce8084a9588d8ff12a00acff224a44498142ae01
Extraction: automated text extraction for offline search; the raw file is authoritative.
-->

# Token revocation

_Web Service Endpoint_

Platforms: Sign in with Apple REST API 1.0

Invalidate the tokens and associated user authorizations for a user when they are no longer associated with your app.

### Discussion

In order to revoke authorization for a user, you must obtain a valid refresh token or access token. If you don’t have either token for the user, you can generate tokens when validating an authorization code. For more information about user tokens and creating client secrets, see [Token validation](https://developer.apple.com/documentation/signinwithapplerestapi/generate-and-validate-tokens).

To invalidate a user’s refresh token, invoke the revoke endpoint with the following HTTP POST method.

```console
curl -v POST "https://appleid.apple.com/auth/revoke" \
-H 'content-type: application/x-www-form-urlencoded' \
-d 'client_id=CLIENT_ID' \
-d 'client_secret=CLIENT_SECRET' \
-d 'token=REFRESH_TOKEN' \
-d 'token_type_hint=refresh_token'
```

Additionally, to invalidate a user’s access token, use the following HTTP POST method.

```console
curl -v POST "https://appleid.apple.com/auth/revoke" \
-H 'content-type: application/x-www-form-urlencoded' \
-d 'client_id=CLIENT_ID' \
-d 'client_secret=CLIENT_SECRET' \
-d 'token=ACCESS_TOKEN' \
-d 'token_type_hint=access_token'
```

For either token revocation request, the `revoke` endpoint returns a `200` response code without a response body after the server invalidates the `token` value, or if the `token` value was previously invalidated. If the response contains an error, please see [ErrorResponse](https://developer.apple.com/documentation/signinwithapplerestapi/errorresponse) for the specific error code provided in the response body.

## Generating and revoking tokens

- [Creating a client secret](https://developer.apple.com/documentation/accountorganizationaldatasharing/creating-a-client-secret) — Generate a signed token to identify your client application.

- [Fetch Apple’s public key to verify token signatures](https://developer.apple.com/documentation/signinwithapplerestapi/fetch-apple's-public-key-for-verifying-token-signature) — Fetch Apple’s public key to verify ID token and server notification signatures.

- [Token validation](https://developer.apple.com/documentation/signinwithapplerestapi/generate-and-validate-tokens) — Validate an authorization grant code delivered to your app to obtain tokens, or validate an existing refresh token.
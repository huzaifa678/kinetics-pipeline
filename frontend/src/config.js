export const API_BASE = import.meta.env.VITE_API_BASE ?? "";

export const oidcConfig = {
  authority: import.meta.env.VITE_COGNITO_AUTHORITY ?? "",
  client_id: import.meta.env.VITE_COGNITO_CLIENT_ID ?? "",
  redirect_uri: import.meta.env.VITE_REDIRECT_URI ?? window.location.origin + "/",
  response_type: "code",
  scope: "openid email inference/predict",
  automaticSilentRenew: true,
};

export const HOSTED_UI = import.meta.env.VITE_COGNITO_HOSTED_UI ?? "";

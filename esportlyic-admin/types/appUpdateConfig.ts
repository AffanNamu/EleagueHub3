// types/appUpdateConfig.ts
//
// Mirrors AppUpdateConfig in lib/core/services/app_update_config.dart --
// the shape of app_config/app_update, the doc AuthRouterRefresh (mobile
// app) reads live to decide whether the installed build is behind and,
// if so, whether that's a skippable nudge or a hard block. Mobile-only:
// the web app never reads this doc.

export interface AppUpdateConfig {
  latestBuildNumber: number;
  latestVersionName: string;
  forceUpdate: boolean;
  releaseNotes: string;
  playStoreUrl: string;
  appStoreUrl: string;
}

/** A partial set of field edits, applied on top of the current doc. */
export type AppUpdateConfigEdit = Partial<AppUpdateConfig>;

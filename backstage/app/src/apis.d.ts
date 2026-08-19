import { AnyApiFactory, ApiRef, BackstageIdentityApi, OAuthApi, OpenIdConnectApi, ProfileInfoApi, SessionApi } from '@backstage/core-plugin-api';
export declare const oidcAuthApiRef: ApiRef<OAuthApi & OpenIdConnectApi & ProfileInfoApi & BackstageIdentityApi & SessionApi>;
export declare const apis: AnyApiFactory[];

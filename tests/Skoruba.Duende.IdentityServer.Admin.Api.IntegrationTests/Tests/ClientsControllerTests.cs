// Copyright (c) Jan Škoruba. All Rights Reserved.
// Licensed under the Apache License, Version 2.0.

using System.Net;
using System.Net.Http.Json;
using System.Collections.Generic;
using System;
using System.Linq;
using System.Threading.Tasks;
using FluentAssertions;
using Skoruba.Duende.IdentityServer.Admin.Api.IntegrationTests.Common;
using Skoruba.Duende.IdentityServer.Admin.Api.IntegrationTests.Tests.Base;
using Skoruba.Duende.IdentityServer.Admin.Api.UnitTests.Mocks;
using Skoruba.Duende.IdentityServer.Admin.UI.Api.Dtos.Clients;
using Xunit;

namespace Skoruba.Duende.IdentityServer.Admin.Api.IntegrationTests.Tests
{
    public class ClientsControllerTests : BaseClassFixture
    {
        public ClientsControllerTests(TestFixture fixture) : base(fixture)
        {
        }

        private void SetupAdminAuthorization()
        {
            Client.DefaultRequestHeaders.Clear();
            SetupAdminClaimsViaHeaders();
        }

        private static List<string> DistinctStrings(List<string> values)
        {
            return values?
                .Where(x => !string.IsNullOrWhiteSpace(x))
                .Distinct(StringComparer.Ordinal)
                .ToList() ?? new List<string>();
        }

        private static List<ClientClaimApiDto> DistinctClaims(List<ClientClaimApiDto> values)
        {
            return values?
                .Where(x => !string.IsNullOrWhiteSpace(x.Type) && !string.IsNullOrWhiteSpace(x.Value))
                .GroupBy(x => $"{x.Type}:{x.Value}", StringComparer.Ordinal)
                .Select(x => x.First())
                .ToList() ?? new List<ClientClaimApiDto>();
        }

        private static List<ClientPropertyApiDto> DistinctProperties(List<ClientPropertyApiDto> values)
        {
            return values?
                .Where(x => !string.IsNullOrWhiteSpace(x.Key))
                .GroupBy(x => x.Key, StringComparer.Ordinal)
                .Select(x => x.First())
                .ToList() ?? new List<ClientPropertyApiDto>();
        }

        private static ClientApiDto BuildClientCreatePayload(string clientId)
        {
            var payload = ClientDtoApiMock.GenerateRandomClient(0);

            payload.Id = 0;
            payload.ClientId = clientId;
            payload.ClientName = clientId;
            payload.AbsoluteRefreshTokenLifetime = 2_592_000;
            payload.AccessTokenLifetime = 3_600;
            payload.AuthorizationCodeLifetime = 300;
            payload.IdentityTokenLifetime = 300;
            payload.SlidingRefreshTokenLifetime = 1_296_000;
            payload.DeviceCodeLifetime = 300;
            payload.RefreshTokenExpiration = payload.RefreshTokenExpiration % 2;
            payload.RefreshTokenUsage = payload.RefreshTokenUsage % 2;
            payload.AccessTokenType = payload.AccessTokenType % 2;
            payload.DPoPValidationMode = 0;
            payload.DPoPClockSkew = TimeSpan.FromMinutes(5);
            payload.AllowedGrantTypes = DistinctStrings(payload.AllowedGrantTypes);
            if (payload.AllowedGrantTypes.Count == 0)
            {
                payload.AllowedGrantTypes.Add("client_credentials");
            }

            payload.AllowedScopes = DistinctStrings(payload.AllowedScopes);
            payload.AllowedCorsOrigins = DistinctStrings(payload.AllowedCorsOrigins);
            payload.RedirectUris = DistinctStrings(payload.RedirectUris);
            payload.PostLogoutRedirectUris = DistinctStrings(payload.PostLogoutRedirectUris);
            payload.IdentityProviderRestrictions = DistinctStrings(payload.IdentityProviderRestrictions);
            payload.AllowedIdentityTokenSigningAlgorithms = DistinctStrings(payload.AllowedIdentityTokenSigningAlgorithms);
            payload.Claims = DistinctClaims(payload.Claims);
            payload.Properties = DistinctProperties(payload.Properties);

            return payload;
        }

        private static void AssertClientCreatePayloadWasPersisted(
            ClientApiDto expected,
            ClientApiDto actual)
        {
            actual.ClientId.Should().Be(expected.ClientId);
            actual.ClientName.Should().Be(expected.ClientName);
            actual.Description.Should().Be(expected.Description);
            actual.Enabled.Should().Be(expected.Enabled);
            actual.RequireClientSecret.Should().Be(expected.RequireClientSecret);
            actual.RequireConsent.Should().Be(expected.RequireConsent);
            actual.RequirePkce.Should().Be(expected.RequirePkce);
            actual.ProtocolType.Should().Be(expected.ProtocolType);
            actual.AccessTokenType.Should().Be(expected.AccessTokenType);
            actual.AccessTokenLifetime.Should().Be(expected.AccessTokenLifetime);
            actual.IdentityTokenLifetime.Should().Be(expected.IdentityTokenLifetime);
            actual.AuthorizationCodeLifetime.Should().Be(expected.AuthorizationCodeLifetime);
            actual.AbsoluteRefreshTokenLifetime.Should().Be(expected.AbsoluteRefreshTokenLifetime);
            actual.SlidingRefreshTokenLifetime.Should().Be(expected.SlidingRefreshTokenLifetime);
            actual.RefreshTokenUsage.Should().Be(expected.RefreshTokenUsage);
            actual.RefreshTokenExpiration.Should().Be(expected.RefreshTokenExpiration);
            actual.AllowOfflineAccess.Should().Be(expected.AllowOfflineAccess);
            actual.AllowAccessTokensViaBrowser.Should().Be(expected.AllowAccessTokensViaBrowser);
            actual.AllowPlainTextPkce.Should().Be(expected.AllowPlainTextPkce);
            actual.AllowRememberConsent.Should().Be(expected.AllowRememberConsent);
            actual.AlwaysIncludeUserClaimsInIdToken.Should().Be(expected.AlwaysIncludeUserClaimsInIdToken);
            actual.UpdateAccessTokenClaimsOnRefresh.Should().Be(expected.UpdateAccessTokenClaimsOnRefresh);
            actual.EnableLocalLogin.Should().Be(expected.EnableLocalLogin);
            actual.RequireRequestObject.Should().Be(expected.RequireRequestObject);
            actual.RequireDPoP.Should().Be(expected.RequireDPoP);
            actual.DPoPValidationMode.Should().Be(expected.DPoPValidationMode);
            actual.RequirePushedAuthorization.Should().Be(expected.RequirePushedAuthorization);
            actual.PushedAuthorizationLifetime.Should().Be(expected.PushedAuthorizationLifetime);
            actual.DeviceCodeLifetime.Should().Be(expected.DeviceCodeLifetime);
            actual.UserCodeType.Should().Be(expected.UserCodeType);
            actual.ClientClaimsPrefix.Should().Be(expected.ClientClaimsPrefix);
            actual.PairWiseSubjectSalt.Should().Be(expected.PairWiseSubjectSalt);
            actual.ClientUri.Should().Be(expected.ClientUri);
            actual.LogoUri.Should().Be(expected.LogoUri);
            actual.InitiateLoginUri.Should().Be(expected.InitiateLoginUri);
            actual.FrontChannelLogoutUri.Should().Be(expected.FrontChannelLogoutUri);
            actual.FrontChannelLogoutSessionRequired.Should().Be(expected.FrontChannelLogoutSessionRequired);
            actual.BackChannelLogoutUri.Should().Be(expected.BackChannelLogoutUri);
            actual.BackChannelLogoutSessionRequired.Should().Be(expected.BackChannelLogoutSessionRequired);
            actual.DPoPClockSkew.Should().Be(expected.DPoPClockSkew);
            actual.AllowedGrantTypes.Should().BeEquivalentTo(expected.AllowedGrantTypes);
            actual.AllowedScopes.Should().BeEquivalentTo(expected.AllowedScopes);
            actual.AllowedCorsOrigins.Should().BeEquivalentTo(expected.AllowedCorsOrigins);
            actual.RedirectUris.Should().BeEquivalentTo(expected.RedirectUris);
            actual.PostLogoutRedirectUris.Should().BeEquivalentTo(expected.PostLogoutRedirectUris);
            actual.IdentityProviderRestrictions.Should().BeEquivalentTo(expected.IdentityProviderRestrictions);
            actual.AllowedIdentityTokenSigningAlgorithms.Should().BeEquivalentTo(expected.AllowedIdentityTokenSigningAlgorithms);
            actual.Claims.Select(x => new { x.Type, x.Value })
                .Should().BeEquivalentTo(expected.Claims.Select(x => new { x.Type, x.Value }));
            actual.Properties.Select(x => new { x.Key, x.Value })
                .Should().BeEquivalentTo(expected.Properties.Select(x => new { x.Key, x.Value }));
        }

        private async Task<ClientApiDto> CreateMachineClientAsync(string clientId)
        {
            var createRequest = BuildClientCreatePayload(clientId);

            var createResponse = await Client.PostAsJsonAsync("api/clients", createRequest);
            createResponse.StatusCode.Should().Be(HttpStatusCode.Created);

            var createdClient = await createResponse.Content.ReadFromJsonAsync<ClientApiDto>();
            createdClient.Should().NotBeNull();
            createdClient!.Id.Should().BeGreaterThan(0);
            createdClient.ClientId.Should().Be(clientId);

            return createdClient;
        }

        [Fact]
        public async Task GetClientsAsAdmin()
        {
            SetupAdminAuthorization();

            var response = await Client.GetAsync("api/clients");

            // Assert
            response.EnsureSuccessStatusCode();
            response.StatusCode.Should().Be(HttpStatusCode.OK);

            var clients = await response.Content.ReadFromJsonAsync<ClientsApiDto>();
            clients.Should().NotBeNull();
            clients!.Clients.Should().NotBeNull();
            clients.TotalCount.Should().BeGreaterOrEqualTo(0);
        }

        [Fact]
        public async Task GetClientsWithoutPermissions()
        {
            Client.DefaultRequestHeaders.Clear();

            var response = await Client.GetAsync("api/clients");

            // Assert
            response.StatusCode.Should().Be(HttpStatusCode.Unauthorized);
        }

        [Fact]
        public async Task GetClientsSupportsSearchByClientId()
        {
            SetupAdminAuthorization();
            var uniqueClientId = $"api_integration_client_{Guid.NewGuid():N}";
            var createdClientId = 0;

            try
            {
                var createdClient = await CreateMachineClientAsync(uniqueClientId);
                createdClientId = createdClient.Id;

                var response = await Client.GetAsync($"api/clients?searchText={uniqueClientId}&page=1&pageSize=10");

                // Assert
                response.EnsureSuccessStatusCode();
                response.StatusCode.Should().Be(HttpStatusCode.OK);

                var clients = await response.Content.ReadFromJsonAsync<ClientsApiDto>();
                clients.Should().NotBeNull();
                clients!.Clients.Should().Contain(x => x.Id == createdClient.Id && x.ClientId == uniqueClientId);
            }
            finally
            {
                if (createdClientId > 0)
                {
                    await Client.DeleteAsync($"api/clients/{createdClientId}");
                }
            }
        }

        [Fact]
        public async Task GetClientByIdReturnsCreatedClient()
        {
            SetupAdminAuthorization();
            var uniqueClientId = $"api_integration_client_{Guid.NewGuid():N}";
            var createdClientId = 0;

            try
            {
                var createdClient = await CreateMachineClientAsync(uniqueClientId);
                createdClientId = createdClient.Id;

                var detailResponse = await Client.GetAsync($"api/clients/{createdClientId}");

                // Assert
                detailResponse.EnsureSuccessStatusCode();
                detailResponse.StatusCode.Should().Be(HttpStatusCode.OK);

                var detail = await detailResponse.Content.ReadFromJsonAsync<ClientApiDto>();
                detail.Should().NotBeNull();
                detail!.Id.Should().Be(createdClientId);
                detail.ClientId.Should().Be(uniqueClientId);
                AssertClientCreatePayloadWasPersisted(createdClient, detail);
            }
            finally
            {
                if (createdClientId > 0)
                {
                    await Client.DeleteAsync($"api/clients/{createdClientId}");
                }
            }
        }

        [Fact]
        public async Task CanInsertClientReturnsFalseForExistingAndTrueForUniqueClientId()
        {
            SetupAdminAuthorization();
            var existingClientId = $"api_integration_client_{Guid.NewGuid():N}";
            var createdClientId = 0;

            try
            {
                var createdClient = await CreateMachineClientAsync(existingClientId);
                createdClientId = createdClient.Id;

                var existingResponse = await Client.GetAsync($"api/clients/CanInsertClient?id=0&clientId={existingClientId}&isCloned=false");
                existingResponse.EnsureSuccessStatusCode();
                var canInsertExisting = await existingResponse.Content.ReadFromJsonAsync<bool>();

                var uniqueClientId = $"api_integration_client_{Guid.NewGuid():N}";
                var uniqueResponse = await Client.GetAsync($"api/clients/CanInsertClient?id=0&clientId={uniqueClientId}&isCloned=false");
                uniqueResponse.EnsureSuccessStatusCode();
                var canInsertUnique = await uniqueResponse.Content.ReadFromJsonAsync<bool>();

                // Assert
                canInsertExisting.Should().BeFalse();
                canInsertUnique.Should().BeTrue();
            }
            finally
            {
                if (createdClientId > 0)
                {
                    await Client.DeleteAsync($"api/clients/{createdClientId}");
                }
            }
        }

        [Fact]
        public async Task ClientCreateUpdateDeleteRoundTripWorksForMachineClient()
        {
            SetupAdminAuthorization();

            var uniqueClientId = $"api_integration_client_{Guid.NewGuid():N}";
            var createdClientId = 0;

            try
            {
                var createdClient = await CreateMachineClientAsync(uniqueClientId);
                createdClientId = createdClient.Id;

                var getResponse = await Client.GetAsync($"api/clients/{createdClientId}");
                getResponse.EnsureSuccessStatusCode();
                var createdDetail = await getResponse.Content.ReadFromJsonAsync<ClientApiDto>();
                createdDetail.Should().NotBeNull();
                createdDetail!.ClientId.Should().Be(uniqueClientId);
                AssertClientCreatePayloadWasPersisted(createdClient, createdDetail);

                createdDetail.ClientName = $"{uniqueClientId}_updated";
                createdDetail.Description = "Updated by API integration test";
                createdDetail.Enabled = false;

                var updateResponse = await Client.PutAsJsonAsync("api/clients", createdDetail);
                updateResponse.StatusCode.Should().Be(HttpStatusCode.NoContent);

                var getUpdatedResponse = await Client.GetAsync($"api/clients/{createdClientId}");
                getUpdatedResponse.EnsureSuccessStatusCode();
                var updatedDetail = await getUpdatedResponse.Content.ReadFromJsonAsync<ClientApiDto>();
                updatedDetail.Should().NotBeNull();
                updatedDetail!.ClientName.Should().Be($"{uniqueClientId}_updated");
                updatedDetail.Description.Should().Be("Updated by API integration test");
                updatedDetail.Enabled.Should().BeFalse();

                var deleteResponse = await Client.DeleteAsync($"api/clients/{createdClientId}");
                deleteResponse.StatusCode.Should().Be(HttpStatusCode.NoContent);
                createdClientId = 0;

                var getDeletedResponse = await Client.GetAsync($"api/clients/{createdClient.Id}");
                getDeletedResponse.StatusCode.Should().Be(HttpStatusCode.BadRequest);
            }
            finally
            {
                if (createdClientId > 0)
                {
                    await Client.DeleteAsync($"api/clients/{createdClientId}");
                }
            }
        }
    }
}

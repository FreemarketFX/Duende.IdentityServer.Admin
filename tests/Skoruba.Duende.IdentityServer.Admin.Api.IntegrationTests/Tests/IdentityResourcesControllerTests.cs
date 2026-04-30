// Copyright (c) Jan Škoruba. All Rights Reserved.
// Licensed under the Apache License, Version 2.0.

using System.Net;
using System.Net.Http.Json;
using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading.Tasks;
using FluentAssertions;
using Skoruba.Duende.IdentityServer.Admin.Api.IntegrationTests.Common;
using Skoruba.Duende.IdentityServer.Admin.Api.IntegrationTests.Tests.Base;
using Skoruba.Duende.IdentityServer.Admin.Api.UnitTests.Mocks;
using Skoruba.Duende.IdentityServer.Admin.UI.Api.Dtos.IdentityResources;
using Xunit;

namespace Skoruba.Duende.IdentityServer.Admin.Api.IntegrationTests.Tests
{
    public class IdentityResourcesControllerTests : BaseClassFixture
    {
        public IdentityResourcesControllerTests(TestFixture fixture) : base(fixture)
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

        private static IdentityResourceApiDto BuildIdentityResourceCreatePayload(string name)
        {
            var payload = IdentityResourceApiDtoMock.GenerateRandomIdentityResource(0);
            payload.Id = 0;
            payload.Name = name;
            payload.UserClaims = DistinctStrings(payload.UserClaims);
            if (payload.UserClaims.Count == 0)
            {
                payload.UserClaims.Add("sub");
            }

            return payload;
        }

        private static void AssertIdentityResourceCreatePayloadWasPersisted(
            IdentityResourceApiDto expected,
            IdentityResourceApiDto actual)
        {
            actual.Name.Should().Be(expected.Name);
            actual.DisplayName.Should().Be(expected.DisplayName);
            actual.Description.Should().Be(expected.Description);
            actual.Enabled.Should().Be(expected.Enabled);
            actual.ShowInDiscoveryDocument.Should().Be(expected.ShowInDiscoveryDocument);
            actual.Required.Should().Be(expected.Required);
            actual.Emphasize.Should().Be(expected.Emphasize);
            actual.UserClaims.Should().BeEquivalentTo(expected.UserClaims);
        }

        private async Task<IdentityResourceApiDto> CreateIdentityResourceAsync(string name)
        {
            var createRequest = BuildIdentityResourceCreatePayload(name);

            var createResponse = await Client.PostAsJsonAsync("api/identityresources", createRequest);
            createResponse.StatusCode.Should().Be(HttpStatusCode.Created);

            var created = await createResponse.Content.ReadFromJsonAsync<IdentityResourceApiDto>();
            created.Should().NotBeNull();
            created!.Id.Should().BeGreaterThan(0);
            created.Name.Should().Be(name);

            return created;
        }

        [Fact]
        public async Task GetIdentityResourcesAsAdmin()
        {
            SetupAdminAuthorization();

            var response = await Client.GetAsync("api/identityresources");

            // Assert
            response.EnsureSuccessStatusCode();
            response.StatusCode.Should().Be(HttpStatusCode.OK);

            var identityResources = await response.Content.ReadFromJsonAsync<IdentityResourcesApiDto>();
            identityResources.Should().NotBeNull();
            identityResources!.IdentityResources.Should().NotBeNull();
            identityResources.TotalCount.Should().BeGreaterOrEqualTo(0);
        }

        [Fact]
        public async Task GetIdentityResourcesWithoutPermissions()
        {
            Client.DefaultRequestHeaders.Clear();

            var response = await Client.GetAsync("api/identityresources");

            // Assert
            response.StatusCode.Should().Be(HttpStatusCode.Unauthorized);
        }

        [Fact]
        public async Task GetIdentityResourcesSupportsSearchByName()
        {
            SetupAdminAuthorization();
            var uniqueName = $"identity_resource_integration_{Guid.NewGuid():N}";
            var createdId = 0;

            try
            {
                var created = await CreateIdentityResourceAsync(uniqueName);
                createdId = created.Id;

                var response = await Client.GetAsync($"api/identityresources?searchText={uniqueName}&page=1&pageSize=10");

                // Assert
                response.EnsureSuccessStatusCode();
                response.StatusCode.Should().Be(HttpStatusCode.OK);

                var identityResources = await response.Content.ReadFromJsonAsync<IdentityResourcesApiDto>();
                identityResources.Should().NotBeNull();
                identityResources!.IdentityResources.Should().Contain(x => x.Id == created.Id && x.Name == uniqueName);
            }
            finally
            {
                if (createdId > 0)
                {
                    await Client.DeleteAsync($"api/identityresources/{createdId}");
                }
            }
        }

        [Fact]
        public async Task GetIdentityResourceByIdReturnsCreatedIdentityResource()
        {
            SetupAdminAuthorization();
            var uniqueName = $"identity_resource_integration_{Guid.NewGuid():N}";
            var createdId = 0;

            try
            {
                var created = await CreateIdentityResourceAsync(uniqueName);
                createdId = created.Id;

                var detailResponse = await Client.GetAsync($"api/identityresources/{createdId}");

                // Assert
                detailResponse.EnsureSuccessStatusCode();
                detailResponse.StatusCode.Should().Be(HttpStatusCode.OK);
                var detail = await detailResponse.Content.ReadFromJsonAsync<IdentityResourceApiDto>();
                detail.Should().NotBeNull();
                detail!.Id.Should().Be(createdId);
                detail.Name.Should().Be(uniqueName);
                AssertIdentityResourceCreatePayloadWasPersisted(created, detail);
            }
            finally
            {
                if (createdId > 0)
                {
                    await Client.DeleteAsync($"api/identityresources/{createdId}");
                }
            }
        }

        [Fact]
        public async Task CanInsertIdentityResourceReturnsFalseForExistingAndTrueForUniqueName()
        {
            SetupAdminAuthorization();
            var existingName = $"identity_resource_integration_{Guid.NewGuid():N}";
            var createdId = 0;

            try
            {
                var created = await CreateIdentityResourceAsync(existingName);
                createdId = created.Id;

                var existingResponse = await Client.GetAsync($"api/identityresources/CanInsertIdentityResource?id=0&name={existingName}");
                existingResponse.EnsureSuccessStatusCode();
                var canInsertExisting = await existingResponse.Content.ReadFromJsonAsync<bool>();

                var uniqueName = $"identity_resource_integration_{Guid.NewGuid():N}";
                var uniqueResponse = await Client.GetAsync($"api/identityresources/CanInsertIdentityResource?id=0&name={uniqueName}");
                uniqueResponse.EnsureSuccessStatusCode();
                var canInsertUnique = await uniqueResponse.Content.ReadFromJsonAsync<bool>();

                // Assert
                canInsertExisting.Should().BeFalse();
                canInsertUnique.Should().BeTrue();
            }
            finally
            {
                if (createdId > 0)
                {
                    await Client.DeleteAsync($"api/identityresources/{createdId}");
                }
            }
        }

        [Fact]
        public async Task IdentityResourceCreateUpdateDeleteRoundTripWorks()
        {
            SetupAdminAuthorization();

            var uniqueName = $"identity_resource_integration_{Guid.NewGuid():N}";
            var createdId = 0;

            try
            {
                var created = await CreateIdentityResourceAsync(uniqueName);
                createdId = created.Id;

                var getResponse = await Client.GetAsync($"api/identityresources/{createdId}");
                getResponse.EnsureSuccessStatusCode();
                var createdDetail = await getResponse.Content.ReadFromJsonAsync<IdentityResourceApiDto>();
                createdDetail.Should().NotBeNull();
                createdDetail!.Name.Should().Be(uniqueName);
                AssertIdentityResourceCreatePayloadWasPersisted(created, createdDetail);

                createdDetail.DisplayName = $"{uniqueName}_updated";
                createdDetail.Description = "Updated by API integration test";
                createdDetail.Enabled = false;
                createdDetail.Required = true;
                createdDetail.Emphasize = true;

                var updateResponse = await Client.PutAsJsonAsync("api/identityresources", createdDetail);
                updateResponse.StatusCode.Should().Be(HttpStatusCode.NoContent);

                var getUpdatedResponse = await Client.GetAsync($"api/identityresources/{createdId}");
                getUpdatedResponse.EnsureSuccessStatusCode();
                var updatedDetail = await getUpdatedResponse.Content.ReadFromJsonAsync<IdentityResourceApiDto>();
                updatedDetail.Should().NotBeNull();
                updatedDetail!.DisplayName.Should().Be($"{uniqueName}_updated");
                updatedDetail.Description.Should().Be("Updated by API integration test");
                updatedDetail.Enabled.Should().BeFalse();
                updatedDetail.Required.Should().BeTrue();
                updatedDetail.Emphasize.Should().BeTrue();

                var deleteResponse = await Client.DeleteAsync($"api/identityresources/{createdId}");
                deleteResponse.StatusCode.Should().Be(HttpStatusCode.NoContent);
                createdId = 0;

                var getDeletedResponse = await Client.GetAsync($"api/identityresources/{created.Id}");
                getDeletedResponse.StatusCode.Should().Be(HttpStatusCode.BadRequest);
            }
            finally
            {
                if (createdId > 0)
                {
                    await Client.DeleteAsync($"api/identityresources/{createdId}");
                }
            }
        }
    }
}

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
using Skoruba.Duende.IdentityServer.Admin.UI.Api.Dtos.ApiResources;
using Xunit;

namespace Skoruba.Duende.IdentityServer.Admin.Api.IntegrationTests.Tests
{
    public class ApiResourcesControllerTests : BaseClassFixture
    {
        public ApiResourcesControllerTests(TestFixture fixture) : base(fixture)
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

        private static ApiResourceApiDto BuildApiResourceCreatePayload(string name)
        {
            var payload = ApiResourceApiDtoMock.GenerateRandomApiResource(0);
            payload.Id = 0;
            payload.Name = name;
            payload.UserClaims = DistinctStrings(payload.UserClaims);
            payload.AllowedAccessTokenSigningAlgorithms = DistinctStrings(payload.AllowedAccessTokenSigningAlgorithms);
            payload.Scopes = DistinctStrings(payload.Scopes);
            if (payload.Scopes.Count == 0)
            {
                payload.Scopes.Add($"scope_{Guid.NewGuid():N}");
            }

            return payload;
        }

        private static void AssertApiResourceCreatePayloadWasPersisted(
            ApiResourceApiDto expected,
            ApiResourceApiDto actual)
        {
            actual.Name.Should().Be(expected.Name);
            actual.DisplayName.Should().Be(expected.DisplayName);
            actual.Description.Should().Be(expected.Description);
            actual.Enabled.Should().Be(expected.Enabled);
            actual.ShowInDiscoveryDocument.Should().Be(expected.ShowInDiscoveryDocument);
            actual.RequireResourceIndicator.Should().Be(expected.RequireResourceIndicator);
            actual.UserClaims.Should().BeEquivalentTo(expected.UserClaims);
            actual.AllowedAccessTokenSigningAlgorithms.Should().BeEquivalentTo(expected.AllowedAccessTokenSigningAlgorithms);
            actual.Scopes.Should().BeEquivalentTo(expected.Scopes);
        }

        private async Task<ApiResourceApiDto> CreateApiResourceAsync(string name)
        {
            var createRequest = BuildApiResourceCreatePayload(name);

            var createResponse = await Client.PostAsJsonAsync("api/apiresources", createRequest);
            createResponse.StatusCode.Should().Be(HttpStatusCode.Created);

            var created = await createResponse.Content.ReadFromJsonAsync<ApiResourceApiDto>();
            created.Should().NotBeNull();
            created!.Id.Should().BeGreaterThan(0);
            created.Name.Should().Be(name);

            return created;
        }

        [Fact]
        public async Task GetApiResourcesAsAdmin()
        {
            SetupAdminAuthorization();

            var response = await Client.GetAsync("api/apiresources");

            // Assert
            response.EnsureSuccessStatusCode();
            response.StatusCode.Should().Be(HttpStatusCode.OK);

            var apiResources = await response.Content.ReadFromJsonAsync<ApiResourcesApiDto>();
            apiResources.Should().NotBeNull();
            apiResources!.ApiResources.Should().NotBeNull();
            apiResources.TotalCount.Should().BeGreaterOrEqualTo(0);
        }

        [Fact]
        public async Task GetApiResourcesWithoutPermissions()
        {
            Client.DefaultRequestHeaders.Clear();

            var response = await Client.GetAsync("api/apiresources");

            // Assert
            response.StatusCode.Should().Be(HttpStatusCode.Unauthorized);
        }

        [Fact]
        public async Task GetApiResourcesSupportsSearchByName()
        {
            SetupAdminAuthorization();
            var uniqueName = $"api_resource_integration_{Guid.NewGuid():N}";
            var createdId = 0;

            try
            {
                var created = await CreateApiResourceAsync(uniqueName);
                createdId = created.Id;

                var response = await Client.GetAsync($"api/apiresources?searchText={uniqueName}&page=1&pageSize=10");

                // Assert
                response.EnsureSuccessStatusCode();
                response.StatusCode.Should().Be(HttpStatusCode.OK);
                var apiResources = await response.Content.ReadFromJsonAsync<ApiResourcesApiDto>();
                apiResources.Should().NotBeNull();
                apiResources!.ApiResources.Should().Contain(x => x.Id == created.Id && x.Name == uniqueName);
            }
            finally
            {
                if (createdId > 0)
                {
                    await Client.DeleteAsync($"api/apiresources/{createdId}");
                }
            }
        }

        [Fact]
        public async Task GetApiResourceByIdReturnsCreatedApiResource()
        {
            SetupAdminAuthorization();
            var uniqueName = $"api_resource_integration_{Guid.NewGuid():N}";
            var createdId = 0;

            try
            {
                var created = await CreateApiResourceAsync(uniqueName);
                createdId = created.Id;

                var detailResponse = await Client.GetAsync($"api/apiresources/{createdId}");

                // Assert
                detailResponse.EnsureSuccessStatusCode();
                detailResponse.StatusCode.Should().Be(HttpStatusCode.OK);
                var detail = await detailResponse.Content.ReadFromJsonAsync<ApiResourceApiDto>();
                detail.Should().NotBeNull();
                detail!.Id.Should().Be(createdId);
                detail.Name.Should().Be(uniqueName);
                AssertApiResourceCreatePayloadWasPersisted(created, detail);
            }
            finally
            {
                if (createdId > 0)
                {
                    await Client.DeleteAsync($"api/apiresources/{createdId}");
                }
            }
        }

        [Fact]
        public async Task CanInsertApiResourceReturnsFalseForExistingAndTrueForUniqueName()
        {
            SetupAdminAuthorization();
            var existingName = $"api_resource_integration_{Guid.NewGuid():N}";
            var createdId = 0;

            try
            {
                var created = await CreateApiResourceAsync(existingName);
                createdId = created.Id;

                var existingResponse = await Client.GetAsync($"api/apiresources/CanInsertApiResource?id=0&name={existingName}");
                existingResponse.EnsureSuccessStatusCode();
                var canInsertExisting = await existingResponse.Content.ReadFromJsonAsync<bool>();

                var uniqueName = $"api_resource_integration_{Guid.NewGuid():N}";
                var uniqueResponse = await Client.GetAsync($"api/apiresources/CanInsertApiResource?id=0&name={uniqueName}");
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
                    await Client.DeleteAsync($"api/apiresources/{createdId}");
                }
            }
        }

        [Fact]
        public async Task ApiResourceCreateUpdateDeleteRoundTripWorks()
        {
            SetupAdminAuthorization();

            var uniqueName = $"api_resource_integration_{Guid.NewGuid():N}";
            var createdId = 0;

            try
            {
                var created = await CreateApiResourceAsync(uniqueName);
                createdId = created.Id;

                var getResponse = await Client.GetAsync($"api/apiresources/{createdId}");
                getResponse.EnsureSuccessStatusCode();
                var createdDetail = await getResponse.Content.ReadFromJsonAsync<ApiResourceApiDto>();
                createdDetail.Should().NotBeNull();
                createdDetail!.Name.Should().Be(uniqueName);
                AssertApiResourceCreatePayloadWasPersisted(created, createdDetail);

                createdDetail.DisplayName = $"{uniqueName}_updated";
                createdDetail.Description = "Updated by API integration test";
                createdDetail.Enabled = false;

                var updateResponse = await Client.PutAsJsonAsync("api/apiresources", createdDetail);
                updateResponse.StatusCode.Should().Be(HttpStatusCode.NoContent);

                var getUpdatedResponse = await Client.GetAsync($"api/apiresources/{createdId}");
                getUpdatedResponse.EnsureSuccessStatusCode();
                var updatedDetail = await getUpdatedResponse.Content.ReadFromJsonAsync<ApiResourceApiDto>();
                updatedDetail.Should().NotBeNull();
                updatedDetail!.DisplayName.Should().Be($"{uniqueName}_updated");
                updatedDetail.Description.Should().Be("Updated by API integration test");
                updatedDetail.Enabled.Should().BeFalse();

                var deleteResponse = await Client.DeleteAsync($"api/apiresources/{createdId}");
                deleteResponse.StatusCode.Should().Be(HttpStatusCode.NoContent);
                createdId = 0;

                var getDeletedResponse = await Client.GetAsync($"api/apiresources/{created.Id}");
                getDeletedResponse.StatusCode.Should().Be(HttpStatusCode.BadRequest);
            }
            finally
            {
                if (createdId > 0)
                {
                    await Client.DeleteAsync($"api/apiresources/{createdId}");
                }
            }
        }
    }
}

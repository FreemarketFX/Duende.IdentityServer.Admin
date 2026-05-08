// Copyright (c) Jan Škoruba. All Rights Reserved.
// Licensed under the Apache License, Version 2.0.

using System;
using System.Net.Http;
using System.Net.Http.Json;
using System.Threading.Tasks;
using Bogus;

namespace Skoruba.Duende.IdentityServer.Admin.Api.IntegrationTests.Tests.Base
{
    public abstract class AdminApiTestBase : BaseClassFixture
    {
        protected const int DefaultPage = 1;
        protected const int DefaultPageSize = 10;
        protected const int ExtendedPageSize = 20;
        protected const int ClaimsPageSize = 50;
        protected const string UpdatedByIntegrationTest = "Updated by API integration test";

        private static readonly Faker TestDataFaker = new();

        protected AdminApiTestBase(TestFixture fixture) : base(fixture)
        {
        }

        protected void SetupAdminAuthorization()
        {
            Client.DefaultRequestHeaders.Clear();
            SetupAdminClaimsViaHeaders();
        }

        protected void ClearAuthorization()
        {
            Client.DefaultRequestHeaders.Clear();
        }

        protected static string UniqueValue(string prefix)
        {
            var token = TestDataFaker.Random.AlphaNumeric(10).ToLowerInvariant();
            return $"{prefix}_{token}_{Guid.NewGuid():N}";
        }

        protected static string ById(string route, int id) => $"{route}/{id}";

        protected static string ById(string route, string id) => $"{route}/{id}";

        protected static string BuildSearchQuery(string route, string searchParameter, string searchValue, int pageSize = DefaultPageSize)
        {
            var encodedValue = Uri.EscapeDataString(searchValue ?? string.Empty);
            return $"{route}?{searchParameter}={encodedValue}&page={DefaultPage}&pageSize={pageSize}";
        }

        protected async Task SafeDeleteAsync(string route, int id)
        {
            if (id > 0)
            {
                await Client.DeleteAsync(ById(route, id));
            }
        }

        protected async Task SafeDeleteAsync(string route, string id)
        {
            if (!string.IsNullOrWhiteSpace(id))
            {
                await Client.DeleteAsync(ById(route, id));
            }
        }

        protected async Task<HttpResponseMessage> DeleteBodyAsync<TRequest>(string route, TRequest body)
        {
            var request = new HttpRequestMessage(HttpMethod.Delete, route)
            {
                Content = JsonContent.Create(body)
            };

            return await Client.SendAsync(request);
        }
    }
}

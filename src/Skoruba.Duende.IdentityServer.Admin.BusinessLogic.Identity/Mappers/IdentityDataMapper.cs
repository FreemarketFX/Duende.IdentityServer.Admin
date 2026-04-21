// Copyright (c) Jan Škoruba. All Rights Reserved.
// Licensed under the Apache License, Version 2.0.

using System;
using System.Collections.Generic;
using System.Linq;
using System.Reflection;
using Microsoft.AspNetCore.Identity;
using Skoruba.Duende.IdentityServer.Admin.BusinessLogic.Identity.Dtos.Identity;
using Skoruba.Duende.IdentityServer.Admin.BusinessLogic.Identity.Mappers.Customization;
using Skoruba.Duende.IdentityServer.Admin.EntityFramework.Extensions.Common;

namespace Skoruba.Duende.IdentityServer.Admin.BusinessLogic.Identity.Mappers
{
    public class IdentityDataMapper<TUserDto, TRoleDto, TUser, TRole, TKey, TUserClaim, TUserLogin, TRoleClaim,
        TUsersDto, TRolesDto, TUserRolesDto, TUserClaimsDto, TUserProviderDto, TUserProvidersDto, TRoleClaimsDto,
        TUserClaimDto, TRoleClaimDto>
        : IIdentityDataMapper<TUserDto, TRoleDto, TUser, TRole, TKey, TUserClaim, TUserLogin, TRoleClaim,
            TUsersDto, TRolesDto, TUserRolesDto, TUserClaimsDto, TUserProviderDto, TUserProvidersDto, TRoleClaimsDto,
            TUserClaimDto, TRoleClaimDto>
        where TUserDto : UserDto<TKey>
        where TRoleDto : RoleDto<TKey>
        where TUser : IdentityUser<TKey>
        where TRole : IdentityRole<TKey>
        where TKey : IEquatable<TKey>
        where TUserClaim : IdentityUserClaim<TKey>
        where TUserLogin : IdentityUserLogin<TKey>
        where TRoleClaim : IdentityRoleClaim<TKey>
        where TUsersDto : UsersDto<TUserDto, TKey>
        where TRolesDto : RolesDto<TRoleDto, TKey>
        where TUserRolesDto : UserRolesDto<TRoleDto, TKey>
        where TUserClaimsDto : UserClaimsDto<TUserClaimDto, TKey>
        where TUserProviderDto : UserProviderDto<TKey>
        where TUserProvidersDto : UserProvidersDto<TUserProviderDto, TKey>
        where TRoleClaimsDto : RoleClaimsDto<TRoleClaimDto, TKey>
        where TUserClaimDto : UserClaimDto<TKey>
        where TRoleClaimDto : RoleClaimDto<TKey>
    {
        private static readonly HashSet<string> UserMappedPropertyNames = new(StringComparer.Ordinal)
        {
            nameof(IdentityUser<TKey>.Id),
            nameof(IdentityUser<TKey>.UserName),
            nameof(IdentityUser<TKey>.Email),
            nameof(IdentityUser<TKey>.EmailConfirmed),
            nameof(IdentityUser<TKey>.PhoneNumber),
            nameof(IdentityUser<TKey>.PhoneNumberConfirmed),
            nameof(IdentityUser<TKey>.LockoutEnabled),
            nameof(IdentityUser<TKey>.LockoutEnd),
            nameof(IdentityUser<TKey>.TwoFactorEnabled),
            nameof(IdentityUser<TKey>.AccessFailedCount),
            nameof(IdentityUser<TKey>.NormalizedUserName),
            nameof(IdentityUser<TKey>.NormalizedEmail),
            nameof(IdentityUser<TKey>.PasswordHash),
            nameof(IdentityUser<TKey>.SecurityStamp),
            nameof(IdentityUser<TKey>.ConcurrencyStamp)
        };

        private static readonly HashSet<string> RoleMappedPropertyNames = new(StringComparer.Ordinal)
        {
            nameof(IdentityRole<TKey>.Id),
            nameof(IdentityRole<TKey>.Name),
            nameof(IdentityRole<TKey>.NormalizedName),
            nameof(IdentityRole<TKey>.ConcurrencyStamp)
        };

        private static readonly HashSet<string> UserClaimMappedPropertyNames = new(StringComparer.Ordinal)
        {
            nameof(IdentityUserClaim<TKey>.Id),
            nameof(IdentityUserClaim<TKey>.UserId),
            nameof(IdentityUserClaim<TKey>.ClaimType),
            nameof(IdentityUserClaim<TKey>.ClaimValue)
        };

        private static readonly HashSet<string> RoleClaimMappedPropertyNames = new(StringComparer.Ordinal)
        {
            nameof(IdentityRoleClaim<TKey>.Id),
            nameof(IdentityRoleClaim<TKey>.RoleId),
            nameof(IdentityRoleClaim<TKey>.ClaimType),
            nameof(IdentityRoleClaim<TKey>.ClaimValue)
        };

        private static readonly HashSet<string> UserProviderMappedPropertyNames = new(StringComparer.Ordinal)
        {
            nameof(UserLoginInfo.ProviderKey),
            nameof(UserLoginInfo.LoginProvider),
            nameof(UserLoginInfo.ProviderDisplayName),
            nameof(UserProviderDto<TKey>.UserId),
            nameof(UserProviderDto<TKey>.UserName)
        };

        private readonly IReadOnlyCollection<IIdentityUserMappingCustomizer<TUserDto, TUser>> _userMappingCustomizers;
        private readonly IReadOnlyCollection<IIdentityRoleMappingCustomizer<TRoleDto, TRole>> _roleMappingCustomizers;

        public IdentityDataMapper(
            IEnumerable<IIdentityUserMappingCustomizer<TUserDto, TUser>> userMappingCustomizers = null,
            IEnumerable<IIdentityRoleMappingCustomizer<TRoleDto, TRole>> roleMappingCustomizers = null)
        {
            _userMappingCustomizers = userMappingCustomizers?.ToArray() ?? Array.Empty<IIdentityUserMappingCustomizer<TUserDto, TUser>>();
            _roleMappingCustomizers = roleMappingCustomizers?.ToArray() ?? Array.Empty<IIdentityRoleMappingCustomizer<TRoleDto, TRole>>();
        }

        public TUsersDto MapPagedUsersToDto(PagedList<TUser> pagedUsers)
        {
            var usersDto = CreateInstance<TUsersDto>();
            usersDto.TotalCount = pagedUsers.TotalCount;
            usersDto.PageSize = pagedUsers.PageSize;
            usersDto.Users = pagedUsers.Data.Select(MapUserToDto).ToList();

            return usersDto;
        }

        public TRolesDto MapPagedRolesToRolesDto(PagedList<TRole> pagedRoles)
        {
            var rolesDto = CreateInstance<TRolesDto>();
            rolesDto.TotalCount = pagedRoles.TotalCount;
            rolesDto.PageSize = pagedRoles.PageSize;
            rolesDto.Roles = pagedRoles.Data.Select(MapRoleToDto).ToList();

            return rolesDto;
        }

        public TUserRolesDto MapPagedRolesToUserRolesDto(PagedList<TRole> pagedRoles)
        {
            var userRolesDto = CreateInstance<TUserRolesDto>();
            userRolesDto.TotalCount = pagedRoles.TotalCount;
            userRolesDto.PageSize = pagedRoles.PageSize;
            userRolesDto.Roles = pagedRoles.Data.Select(MapRoleToDto).ToList();

            return userRolesDto;
        }

        public TUserClaimsDto MapPagedUserClaimsToDto(PagedList<TUserClaim> pagedClaims)
        {
            var userClaimsDto = CreateInstance<TUserClaimsDto>();
            userClaimsDto.TotalCount = pagedClaims.TotalCount;
            userClaimsDto.PageSize = pagedClaims.PageSize;
            userClaimsDto.Claims = pagedClaims.Data.Select(MapUserClaimToClaimDto).ToList();

            return userClaimsDto;
        }

        public TRoleClaimsDto MapPagedRoleClaimsToDto(PagedList<TRoleClaim> pagedClaims)
        {
            var roleClaimsDto = CreateInstance<TRoleClaimsDto>();
            roleClaimsDto.TotalCount = pagedClaims.TotalCount;
            roleClaimsDto.PageSize = pagedClaims.PageSize;
            roleClaimsDto.Claims = pagedClaims.Data.Select(MapRoleClaimToClaimDto).ToList();

            return roleClaimsDto;
        }

        public TUserDto MapUserToDto(TUser source)
        {
            var userDto = CreateInstance<TUserDto>();
            userDto.Id = source.Id;
            userDto.UserName = source.UserName;
            userDto.Email = source.Email;
            userDto.EmailConfirmed = source.EmailConfirmed;
            userDto.PhoneNumber = source.PhoneNumber;
            userDto.PhoneNumberConfirmed = source.PhoneNumberConfirmed;
            userDto.LockoutEnabled = source.LockoutEnabled;
            userDto.TwoFactorEnabled = source.TwoFactorEnabled;
            userDto.AccessFailedCount = source.AccessFailedCount;
            userDto.LockoutEnd = source.LockoutEnd;
            CopyMatchingProperties(source, userDto, UserMappedPropertyNames);
            ApplyUserEntityToDtoCustomizers(source, userDto);

            return userDto;
        }

        public TRoleDto MapRoleToDto(TRole source)
        {
            var roleDto = CreateInstance<TRoleDto>();
            roleDto.Id = source.Id;
            roleDto.Name = source.Name;
            CopyMatchingProperties(source, roleDto, RoleMappedPropertyNames);
            ApplyRoleEntityToDtoCustomizers(source, roleDto);

            return roleDto;
        }

        public TUserClaimsDto MapUserClaimToClaimsDto(TUserClaim source)
        {
            var claimDto = CreateInstance<TUserClaimsDto>();
            claimDto.ClaimId = source.Id;
            claimDto.UserId = source.UserId;
            claimDto.ClaimType = source.ClaimType;
            claimDto.ClaimValue = source.ClaimValue;
            CopyMatchingProperties(source, claimDto, UserClaimMappedPropertyNames);

            return claimDto;
        }

        public TRoleClaimsDto MapRoleClaimToRoleClaimsDto(TRoleClaim source)
        {
            var claimDto = CreateInstance<TRoleClaimsDto>();
            claimDto.ClaimId = source.Id;
            claimDto.RoleId = source.RoleId;
            claimDto.ClaimType = source.ClaimType;
            claimDto.ClaimValue = source.ClaimValue;
            CopyMatchingProperties(source, claimDto, RoleClaimMappedPropertyNames);

            return claimDto;
        }

        public TUserProviderDto MapUserLoginToProviderDto(TUserLogin source)
        {
            var providerDto = CreateInstance<TUserProviderDto>();
            providerDto.UserId = source.UserId;
            providerDto.ProviderKey = source.ProviderKey;
            providerDto.LoginProvider = source.LoginProvider;
            providerDto.ProviderDisplayName = source.ProviderDisplayName;
            CopyMatchingProperties(source, providerDto, UserProviderMappedPropertyNames);

            return providerDto;
        }

        public TUserProvidersDto MapUserLoginInfosToProvidersDto(List<UserLoginInfo> source)
        {
            var providersDto = CreateInstance<TUserProvidersDto>();
            providersDto.Providers = source.Select(MapUserLoginInfoToProviderDto).ToList();

            return providersDto;
        }

        public TUser MapUserDtoToEntity(TUserDto user)
        {
            var userEntity = CreateInstance<TUser>();

            if (!user.IsDefaultId())
            {
                userEntity.Id = user.Id;
            }

            MapUserDtoToEntity(user, userEntity);

            return userEntity;
        }

        public TRole MapRoleDtoToEntity(TRoleDto role)
        {
            var roleEntity = CreateInstance<TRole>();

            if (!role.IsDefaultId())
            {
                roleEntity.Id = role.Id;
            }

            MapRoleDtoToEntity(role, roleEntity);

            return roleEntity;
        }

        public void MapUserDtoToEntity(TUserDto source, TUser destination)
        {
            ArgumentNullException.ThrowIfNull(source);
            ArgumentNullException.ThrowIfNull(destination);

            destination.UserName = source.UserName;
            destination.Email = source.Email;
            destination.EmailConfirmed = source.EmailConfirmed;
            destination.PhoneNumber = source.PhoneNumber;
            destination.PhoneNumberConfirmed = source.PhoneNumberConfirmed;
            destination.LockoutEnabled = source.LockoutEnabled;
            destination.LockoutEnd = source.LockoutEnd;
            destination.TwoFactorEnabled = source.TwoFactorEnabled;
            destination.AccessFailedCount = source.AccessFailedCount;
            CopyMatchingProperties(source, destination, UserMappedPropertyNames);
            ApplyUserDtoToEntityCustomizers(source, destination);
        }

        public void MapRoleDtoToEntity(TRoleDto source, TRole destination)
        {
            ArgumentNullException.ThrowIfNull(source);
            ArgumentNullException.ThrowIfNull(destination);

            destination.Name = source.Name;
            CopyMatchingProperties(source, destination, RoleMappedPropertyNames);
            ApplyRoleDtoToEntityCustomizers(source, destination);
        }

        public TUserClaim MapUserClaimsDtoToEntity(TUserClaimsDto claimsDto)
        {
            var userClaim = CreateInstance<TUserClaim>();
            userClaim.Id = claimsDto.ClaimId;
            userClaim.UserId = claimsDto.UserId;
            userClaim.ClaimType = claimsDto.ClaimType;
            userClaim.ClaimValue = claimsDto.ClaimValue;
            CopyMatchingProperties(claimsDto, userClaim, UserClaimMappedPropertyNames);

            return userClaim;
        }

        public TRoleClaim MapRoleClaimsDtoToEntity(TRoleClaimsDto claimsDto)
        {
            var roleClaim = CreateInstance<TRoleClaim>();
            roleClaim.Id = claimsDto.ClaimId;
            roleClaim.RoleId = claimsDto.RoleId;
            roleClaim.ClaimType = claimsDto.ClaimType;
            roleClaim.ClaimValue = claimsDto.ClaimValue;
            CopyMatchingProperties(claimsDto, roleClaim, RoleClaimMappedPropertyNames);

            return roleClaim;
        }

        private TUserClaimDto MapUserClaimToClaimDto(TUserClaim source)
        {
            var claimDto = CreateInstance<TUserClaimDto>();
            claimDto.ClaimId = source.Id;
            claimDto.UserId = source.UserId;
            claimDto.ClaimType = source.ClaimType;
            claimDto.ClaimValue = source.ClaimValue;
            CopyMatchingProperties(source, claimDto, UserClaimMappedPropertyNames);

            return claimDto;
        }

        private TRoleClaimDto MapRoleClaimToClaimDto(TRoleClaim source)
        {
            var claimDto = CreateInstance<TRoleClaimDto>();
            claimDto.ClaimId = source.Id;
            claimDto.RoleId = source.RoleId;
            claimDto.ClaimType = source.ClaimType;
            claimDto.ClaimValue = source.ClaimValue;
            CopyMatchingProperties(source, claimDto, RoleClaimMappedPropertyNames);

            return claimDto;
        }

        private TUserProviderDto MapUserLoginInfoToProviderDto(UserLoginInfo source)
        {
            var providerDto = CreateInstance<TUserProviderDto>();
            providerDto.ProviderKey = source.ProviderKey;
            providerDto.LoginProvider = source.LoginProvider;
            providerDto.ProviderDisplayName = source.ProviderDisplayName;
            CopyMatchingProperties(source, providerDto, UserProviderMappedPropertyNames);

            return providerDto;
        }

        private void ApplyUserDtoToEntityCustomizers(TUserDto source, TUser destination)
        {
            foreach (var customizer in _userMappingCustomizers)
            {
                customizer.MapDtoToEntity(source, destination);
            }
        }

        private void ApplyUserEntityToDtoCustomizers(TUser source, TUserDto destination)
        {
            foreach (var customizer in _userMappingCustomizers)
            {
                customizer.MapEntityToDto(source, destination);
            }
        }

        private void ApplyRoleDtoToEntityCustomizers(TRoleDto source, TRole destination)
        {
            foreach (var customizer in _roleMappingCustomizers)
            {
                customizer.MapDtoToEntity(source, destination);
            }
        }

        private void ApplyRoleEntityToDtoCustomizers(TRole source, TRoleDto destination)
        {
            foreach (var customizer in _roleMappingCustomizers)
            {
                customizer.MapEntityToDto(source, destination);
            }
        }

        private static TEntity CreateInstance<TEntity>() where TEntity : class
        {
            var instance = Activator.CreateInstance<TEntity>();
            if (instance == null)
            {
                throw new InvalidOperationException($"Cannot create an instance of {typeof(TEntity).FullName}.");
            }

            return instance;
        }

        private static void CopyMatchingProperties<TSource, TDestination>(TSource source, TDestination destination, IReadOnlySet<string> excludedProperties)
        {
            if (source == null || destination == null)
            {
                return;
            }

            var sourceProperties = typeof(TSource)
                .GetProperties(BindingFlags.Public | BindingFlags.Instance)
                .Where(x => x.CanRead && x.GetIndexParameters().Length == 0)
                .OrderBy(x => GetInheritanceDistance(typeof(TSource), x.DeclaringType))
                .GroupBy(x => x.Name, StringComparer.Ordinal)
                .ToDictionary(x => x.Key, x => x.First(), StringComparer.Ordinal);

            foreach (var destinationProperty in typeof(TDestination).GetProperties(BindingFlags.Public | BindingFlags.Instance)
                         .Where(x => x.CanWrite && x.GetIndexParameters().Length == 0))
            {
                if (excludedProperties.Contains(destinationProperty.Name))
                {
                    continue;
                }

                if (!sourceProperties.TryGetValue(destinationProperty.Name, out var sourceProperty))
                {
                    continue;
                }

                if (!destinationProperty.PropertyType.IsAssignableFrom(sourceProperty.PropertyType))
                {
                    continue;
                }

                destinationProperty.SetValue(destination, sourceProperty.GetValue(source));
            }
        }

        private static int GetInheritanceDistance(Type targetType, Type declaringType)
        {
            if (declaringType == null)
            {
                return int.MaxValue;
            }

            var distance = 0;
            for (var currentType = targetType; currentType != null; currentType = currentType.BaseType)
            {
                if (currentType == declaringType)
                {
                    return distance;
                }

                distance++;
            }

            return int.MaxValue;
        }
    }
}

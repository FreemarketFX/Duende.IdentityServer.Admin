// Copyright (c) Jan Škoruba. All Rights Reserved.
// Licensed under the Apache License, Version 2.0.

namespace Skoruba.Duende.IdentityServer.Admin.BusinessLogic.Identity.Mappers.Customization
{
    public interface IIdentityUserMappingCustomizer<TUserDto, TUser>
    {
        void MapDtoToEntity(TUserDto source, TUser destination);
        void MapEntityToDto(TUser source, TUserDto destination);
    }
}

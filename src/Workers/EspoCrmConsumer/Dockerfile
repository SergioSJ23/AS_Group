FROM mcr.microsoft.com/dotnet/sdk:10.0-alpine AS build
WORKDIR /src
COPY EspoCrmConsumer.csproj .
RUN dotnet restore
COPY . .
RUN dotnet publish -c Release -o /app/published

FROM mcr.microsoft.com/dotnet/aspnet:10.0-alpine AS runtime
WORKDIR /app
COPY --from=build /app/published .
ENTRYPOINT ["dotnet", "EspoCrmConsumer.dll"]

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

/*
	Add received Bus geolocation data and check if buses are
	inside any defined GeoFence. JSON must be like:

	{
		"DirectionId": 1,
		"RouteId": 100001,
		"VehicleId": 2,
		"Position": {
			"Latitude": 47.61705102765316,
			"Longitude": -122.14291865504012 
		},
		"TimestampUTC": "20201031"
	}
}
*/
CREATE   procedure [web].[AddBusData]
@payload nvarchar(max) 
as
begin	
	set nocount on
	set xact_abort on
	set tran isolation level serializable
	begin tran

	if (isjson(@payload) != 1) begin;
		throw 50000, 'Payload is not a valid JSON document', 16;
	end;

	declare @ids as table (id int);

	-- insert bus data
	insert into dbo.[BusData] 
		([DirectionId], [RouteId], [VehicleId], [Location], [TimestampUTC])
	output
		[Inserted].Id into @ids
	select
		[DirectionId], 
		[RouteId], 
		[VehicleId], 
		geography::Point([Latitude], [Longitude], 4326) as [Location], 
		[TimestampUTC]
	from
		openjson(@payload) with (
			[DirectionId] int,
			[RouteId] int,
			[VehicleId] int,
			[Latitude] decimal(10,6) '$.Position.Latitude',
			[Longitude] decimal(10,6) '$.Position.Longitude',
			[TimestampUTC] datetime2(7)
		)
		
	-- Get details of inserted data
	select * into #t from dbo.[BusData] where id  in (select i.id from @ids i);

	-- Find geofences in which the vehicle is in
	select 
		t.[Id] as BusDataId,
		t.[VehicleId],
		t.[DirectionId],
		t.[TimestampUTC],
		t.[RouteId],		
		g.Id as GeoFenceId
	into
		#g
	from 
		dbo.GeoFences g 
	right join
		#t t on g.GeoFence.STContains(t.[Location]) = 1;

	-- Calculate status
	select
		c.BusDataId,
		coalesce(a.[GeoFenceId], c.[GeoFenceId]) as GeoFenceId,
		coalesce(a.[DirectionId], c.[DirectionId]) as DirectionId,
		coalesce(a.[VehicleId], c.[VehicleId]) as VehicleId,
		c.[RouteId],
		c.[TimestampUTC],
		case 
			when a.GeoFenceId is null and c.GeoFenceId is not null then 'Enter'
			when a.GeoFenceId is not null and c.GeoFenceId is null then 'Exit'		
		end as [Status]
	into
		#s 
	from
		#g c
	full outer join
		dbo.GeoFencesActive a on c.DirectionId = a.DirectionId and c.VehicleId = a.VehicleId;
	
	-- Delete exited geofences
	delete 
		a
	from
		dbo.GeoFencesActive a
	inner join
		#s s on a.VehicleId = s.VehicleId and s.DirectionId = a.DirectionId and s.[Status] = 'Exit';

	-- Insert entered geofences
	insert into dbo.GeoFencesActive 
		([GeoFenceId], [DirectionId], [VehicleId])
	select
		[GeoFenceId], [DirectionId], [VehicleId]
	from
		#s s
	where 
		s.[Status] = 'Enter';

	-- Insert Log
	insert into dbo.GeoFenceLog 
		(GeoFenceId, BusDataId, [RouteId], [VehicleId], [TimestampUTC], [Status])
	select
		GeoFenceId, BusDataId, [RouteId], [VehicleId], [TimestampUTC], isnull([Status], 'In')
	from
		#s s
	where
		s.[GeoFenceId] is not null
	and
		s.[BusDataId] is not null

	-- Return Entered or Exited geofences
	select
	((
		select
			s.[BusDataId],  
			s.[VehicleId],
			s.[DirectionId],  
			s.[RouteId], 
			r.[ShortName] as RouteName,
			s.[GeoFenceId], 
			gf.[Name] as GeoFence,
			s.[Status] as GeoFenceStatus,
			s.[TimestampUTC]
		from
			#s s
		inner join
			dbo.[GeoFences] gf on s.[GeoFenceId] = gf.[Id]
		inner join
			dbo.[Routes] r on s.[RouteId] = r.[Id]
		where
			s.[Status] is not null and s.[GeoFenceId] is not null
		for 
			json path
	)) as ActivatedGeoFences
	commit
end
GO

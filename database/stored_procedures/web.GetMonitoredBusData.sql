SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

/*
	Return last geospatial data for bus closest to the GeoFence
*/
CREATE procedure [web].[GetMonitoredBusData]
@routeId int,
@geofenceId int
as
begin
	with cte as
	(
		-- Get the latest location of all the buses in the given route
		select top (1) with ties 
			*  
		from 
			dbo.[BusData] 
		where
			[RouteId] = @routeId
		order by 
			[ReceivedAtUTC] desc
	),
	cte2 as
	(
		-- Get the closest to the GeoFence
		select top (1)
			c.[VehicleId],
			gf.[GeoFence],
			c.[Location].STDistance(gf.[GeoFence]) as d
		from
			[cte] c
		cross join
			dbo.[GeoFences] gf
		where
			gf.[Id] = @geofenceId
		order by
			d 
	), cte3 as
	(
	-- Take the last 50 points 
	select top (50)
		[bd].[VehicleId],
		[bd].[DirectionId],
		[bd].[Location] as l,
		[bd].[Location].STDistance([GeoFence]) as d
	from
		dbo.[BusData] bd
	inner join
		cte2 on [cte2].[VehicleId] = [bd].[VehicleId]
	order by 
		id desc
	)
	-- Return only the points that are withing 5 Km
	select 
	((
		select
			geography::UnionAggregate(l).ToString() as [busData],
			(select [GeoFence].ToString() from dbo.[GeoFences] where Id = @geofenceId) as [geoFence]
		from
			cte3
		where
			d < 5000
		for json auto, include_null_values, without_array_wrapper
	)) as locationData
end
GO

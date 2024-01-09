SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

/*
	Return the Routes (and thus the buses) to monitor
*/
CREATE   procedure [web].[GetMonitoredRoutes]
as
begin
	select 
	((	
		select RouteId from dbo.[MonitoredRoutes] for json auto
	)) as MonitoredRoutes
end
GO

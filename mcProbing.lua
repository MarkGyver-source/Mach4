-----------------------------------------------------------------------------
-- Name:        Auto Tool Setting Module
-- Author:      T Lamontagne
-- Modified by: T Lamontagne/Rob Gaudette 9/17/2015
---------------------------------------------------------------------
-- Modified by: B Price 10/17/2016 Replaced #var #s with constants
--Updated function Probing.SetFixOffset
--2134	mc.SV_FEEDRATE
--4001	mc.SV_MOD_GROUP_1
--4002	mc.SV_MOD_GROUP_2
--4003	mc.SV_MOD_GROUP_3
--4102	mc.SV_ORIGIN_OFFSET_Z
--5061	mc.SV_PROBE_POS_X
--5062	mc.SV_PROBE_POS_Y
--5063	mc.SV_PROBE_POS_Z 
--5071	mc.SV_PROBE_MACH_POS_X
--5072	mc.SV_PROBE_MACH_POS_Y
--5073	mc.SV_PROBE_MACH_POS_Z
-------------------------------------------------------------------
-- Modified by: B Price 7/19/2017 Defined "inst" in several functions
-------------------------------------------------------------------
-- Created:     03/11/2015
-- Copyright:   (c) 2015 Newfangled Solutions. All rights reserved.
-- License:    
-----------------------------------------------------------------------------
local Probing = {}


function Probing.SingleSurfY(ypos, work)
	local inst = mc.mcGetInstance()
	------------- Errors -------------
	if (ypos == nil) then
		mc.mcCntlSetLastError(inst, "Probe: Y position not input")
		do return end
	end
	
	------------- Define Vars -------------
	Probing.NilVars(100, 150)
	local YPos = tonumber(ypos)
	
	local SetWork = tonumber(work)
	
	local ProbeRad = mc.mcProfileGetDouble(inst, "ProbingSettings", "Radius", 0.000)
	local XOffset = mc.mcProfileGetDouble(inst, "ProbingSettings", "XOffset", 0.000)
	local YOffset = mc.mcProfileGetDouble(inst, "ProbingSettings", "YOffset", 0.000)
	local OffsetNum = mc.mcProfileGetDouble(inst , "ProbingSettings", "OffsetNum", 0.000)
	local SlowFeed = mc.mcProfileGetDouble(inst , "ProbingSettings", "SlowFeed", 0.000)
	local FastFeed = mc.mcProfileGetDouble(inst , "ProbingSettings", "FastFeed", 0.000)
	local BackOff = mc.mcProfileGetDouble(inst , "ProbingSettings", "BackOff", 0.000)
	local OverShoot = mc.mcProfileGetDouble(inst , "ProbingSettings", "OverShoot", 0.000)
	local InPosZone = mc.mcProfileGetDouble(inst , "ProbingSettings", "InPosZone", 0.000)
	local ProbeCode = mc.mcProfileGetDouble(inst , "ProbingSettings", "GCode", 0.000)
	
	------------- Get current state -------------
	local CurFeed = mc.mcCntlGetPoundVar(inst, mc.SV_FEEDRATE)
	local CurZOffset = mc.mcCntlGetPoundVar(inst, mc.SV_ORIGIN_OFFSET_Z)
	local CurFeedMode = mc.mcCntlGetPoundVar(inst, mc.SV_MOD_GROUP_1)
	local CurAbsMode = mc.mcCntlGetPoundVar(inst, mc.SV_MOD_GROUP_3)
	local CurPosition = mc.mcAxisGetPos(inst, mc.Y_AXIS)
	
	
	------------- Check Probe -------------
	rc = Probing.CheckProbe(1, ProbeCode); if not rc then; do return end; end
	
	------------- Check direction -------------
	if (CurPosition > YPos) then
		BackOff = -BackOff
		OverShoot = -OverShoot
		ProbeRad = -ProbeRad
	end
	
	------------- Probe Surface -------------
	local ProbeTo = YPos + OverShoot
	local rc = mc.mcCntlGcodeExecuteWait(inst, "G0 G90 G40 G80")
	mm.ReturnCode(rc)
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G%.1f Y%.4f F%.1f", ProbeCode, ProbeTo, FastFeed))
	mm.ReturnCode(rc)
	rc = Probing.CheckProbe(0, ProbeCode); if not rc then; do return end; end
	local ProbePoint = mc.mcCntlGetPoundVar(inst, mc.SV_PROBE_POS_Y)
	local RetractPoint = ProbePoint - BackOff
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G1 Y%.4f F%.1f", RetractPoint, FastFeed))
	mm.ReturnCode(rc)
	--Measure
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G%.1f Y%.4f F%.1f", ProbeCode, ProbeTo, SlowFeed))
	mm.ReturnCode(rc)
	rc = Probing.CheckProbe(0, ProbeCode); if not rc then; do return end; end
	local MeasPointABS = mc.mcCntlGetPoundVar(inst, mc.SV_PROBE_POS_Y)
	local MeasPointMACH = mc.mcCntlGetPoundVar(inst,mc.SV_PROBE_MACH_POS_Y)
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G1 Y%.4f F%.1f", CurPosition, FastFeed))
	mm.ReturnCode(rc)
	
	------------- Calculate and set offset/vars -------------
	MeasPointABS = MeasPointABS + ProbeRad + YOffset
	MeasPointMACH = MeasPointMACH + ProbeRad + YOffset
	local PosError = MeasPointABS - YPos
	
	mc.mcCntlSetPoundVar(inst, 132, MeasPointMACH)
	mc.mcCntlSetPoundVar(inst, 142, MeasPointABS)
	mc.mcCntlSetPoundVar(inst, 144, MeasPointABS)
	mc.mcCntlSetPoundVar(inst, 136, PosError)
	
	if (SetWork == 1) then
		Probing.SetFixOffset(nil, MeasPointMACH, nil)
	end
	
	------------- Reset State ------------------------------------
	mc.mcCntlSetPoundVar(inst, mc.SV_FEEDRATE, CurFeed)
	mc.mcCntlSetPoundVar(inst, mc.SV_MOD_GROUP_1, CurFeedMode)
	mc.mcCntlSetPoundVar(inst, mc.SV_MOD_GROUP_3, CurAbsMode)
end


function Probing.InternalCorner(xpos, ypos, xinc, yinc, work)
	local inst = mc.mcGetInstance()
	------------- Errors -------------
	if (xpos == nil) then
		mc.mcCntlSetLastError(inst, "Probe: X position not input")
		do return end
	end
	if (ypos == nil) then
		mc.mcCntlSetLastError(inst, "Probe: Y position not input")
		do return end
	end
	if (yinc ~= nil) and (xinc == nil) then
		xinc = yinc
	end
	
	------------- Define Vars -------------
	Probing.NilVars(100, 150)
	local XPos = tonumber(xpos)
	local YPos = tonumber(ypos)
	local XInc = tonumber(xinc)
	local YInc = tonumber(yinc)
	if (yinc == nil) then
		XInc = 0
		YInc = 0
	end
	
	local SetWork = tonumber(work)
	
	local MeasPointX1ABS
	local MeasPointX1MACH
	local MeasPointX2ABS
	local MeasPointX2MACH
	
	local MeasPointY1ABS
	local MeasPointY1MACH
	local MeasPointY2ABS
	local MeasPointY2MACH
	
	local ProbeRad = mc.mcProfileGetDouble(inst, "ProbingSettings", "Radius", 0.000)
	local XOffset = mc.mcProfileGetDouble(inst, "ProbingSettings", "XOffset", 0.000)
	local YOffset = mc.mcProfileGetDouble(inst, "ProbingSettings", "YOffset", 0.000)
	local OffsetNum = mc.mcProfileGetDouble(inst , "ProbingSettings", "OffsetNum", 0.000)
	local SlowFeed = mc.mcProfileGetDouble(inst , "ProbingSettings", "SlowFeed", 0.000)
	local FastFeed = mc.mcProfileGetDouble(inst , "ProbingSettings", "FastFeed", 0.000)
	local BackOff = mc.mcProfileGetDouble(inst , "ProbingSettings", "BackOff", 0.000)
	local OverShoot = mc.mcProfileGetDouble(inst , "ProbingSettings", "OverShoot", 0.000)
	local InPosZone = mc.mcProfileGetDouble(inst , "ProbingSettings", "InPosZone", 0.000)
	local ProbeCode = mc.mcProfileGetDouble(inst , "ProbingSettings", "GCode", 0.000)
	
	------------- Get current state -------------
	local CurFeed = mc.mcCntlGetPoundVar(inst, mc.SV_FEEDRATE)
	local CurZOffset = mc.mcCntlGetPoundVar(inst, mc.SV_ORIGIN_OFFSET_Z)
	local CurFeedMode = mc.mcCntlGetPoundVar(inst, mc.SV_MOD_GROUP_1)
	local CurAbsMode = mc.mcCntlGetPoundVar(inst, mc.SV_MOD_GROUP_3)
	local CurXPosition = mc.mcAxisGetPos(inst, mc.X_AXIS)
	local CurYPosition = mc.mcAxisGetPos(inst, mc.Y_AXIS)
	
	
	------------- Check Probe -------------
	rc = Probing.CheckProbe(1, ProbeCode); if not rc then; do return end; end
	
	------------- Check direction -------------
	if (CurXPosition > XPos) then
		XBackOff = -BackOff
		XOverShoot = -OverShoot
		XProbeRad = -ProbeRad
	else
		XBackOff = BackOff
		XOverShoot = OverShoot
		XProbeRad = ProbeRad
	end
	
	if (CurYPosition > YPos) then
		YBackOff = -BackOff
		YOverShoot = -OverShoot
		YProbeRad = -ProbeRad
	else
		YBackOff = BackOff
		YOverShoot = OverShoot
		YProbeRad = ProbeRad
	end
	
	------------- Probe X Surface -------------
	local ProbeTo = XPos + XOverShoot
	local rc = mc.mcCntlGcodeExecuteWait(inst, "G0 G90 G40 G80")
	mm.ReturnCode(rc)
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G%.1f X%.4f F%.1f", ProbeCode, ProbeTo, FastFeed))
	mm.ReturnCode(rc)
	rc = Probing.CheckProbe(0, ProbeCode); if not rc then; do return end; end
	local ProbePoint = mc.mcCntlGetPoundVar(inst, mc.SV_PROBE_POS_X)
	local RetractPoint = ProbePoint - XBackOff
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G1 X%.4f F%.1f", RetractPoint, FastFeed))
	mm.ReturnCode(rc)
	--Measure
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G%.1f X%.4f F%.1f", ProbeCode, ProbeTo, SlowFeed))
	mm.ReturnCode(rc)
	rc = Probing.CheckProbe(0, ProbeCode); if not rc then; do return end; end
	MeasPointX1ABS = mc.mcCntlGetPoundVar(inst, mc.SV_PROBE_POS_X) + XProbeRad + XOffset
	MeasPointX1MACH = mc.mcCntlGetPoundVar(inst,mc.SV_PROBE_MACH_POS_X) + XProbeRad + XOffset
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G1 X%.4f F%.1f", CurXPosition, FastFeed))
	mm.ReturnCode(rc)
	if (YInc ~= 0) then
		rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G%.1f Y%.4f F%.1f", ProbeCode, CurYPosition + YInc, FastFeed))
		mm.ReturnCode(rc)
		rc = Probing.CheckProbe(1, ProbeCode); if not rc then; do return end; end
		rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G%.1f X%.4f F%.1f", ProbeCode, ProbeTo, FastFeed))
		mm.ReturnCode(rc)
		rc = Probing.CheckProbe(0, ProbeCode); if not rc then; do return end; end
		local ProbePoint = mc.mcCntlGetPoundVar(inst, mc.SV_PROBE_POS_X)
		local RetractPoint = ProbePoint - XBackOff
		rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G1 X%.4f F%.1f", RetractPoint, FastFeed))
		mm.ReturnCode(rc)
		--Measure
		rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G%.1f X%.4f F%.1f", ProbeCode, ProbeTo, SlowFeed))
		mm.ReturnCode(rc)
		rc = Probing.CheckProbe(0, ProbeCode); if not rc then; do return end; end
		MeasPointX2ABS = mc.mcCntlGetPoundVar(inst, mc.SV_PROBE_POS_X) + XProbeRad + XOffset
		MeasPointX2MACH = mc.mcCntlGetPoundVar(inst,mc.SV_PROBE_MACH_POS_X) + XProbeRad + XOffset
		rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G1 X%.4f F%.1f", CurXPosition, FastFeed))
		mm.ReturnCode(rc)
		rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G1 Y%.4f F%.1f", CurYPosition, FastFeed))
		mm.ReturnCode(rc)
	end
	
		------------- Probe Y Surface -------------
	local ProbeTo = YPos + YOverShoot
	rc = mc.mcCntlGcodeExecuteWait(inst, "G0 G90 G40 G80")
	mm.ReturnCode(rc)
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G%.1f Y%.4f F%.1f", ProbeCode, ProbeTo, FastFeed))
	mm.ReturnCode(rc)
	rc = Probing.CheckProbe(0, ProbeCode); if not rc then; do return end; end
	local ProbePoint = mc.mcCntlGetPoundVar(inst, mc.SV_PROBE_POS_Y)
	local RetractPoint = ProbePoint - YBackOff
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G1 Y%.4f F%.1f", RetractPoint, FastFeed))
	mm.ReturnCode(rc)
	--Measure
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G%.1f Y%.4f F%.1f", ProbeCode, ProbeTo, SlowFeed))
	mm.ReturnCode(rc)
	rc = Probing.CheckProbe(0, ProbeCode); if not rc then; do return end; end
	MeasPointY1ABS = mc.mcCntlGetPoundVar(inst, mc.SV_PROBE_POS_Y) + YProbeRad + YOffset
	MeasPointY1MACH = mc.mcCntlGetPoundVar(inst,mc.SV_PROBE_MACH_POS_Y) + YProbeRad + YOffset
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G01 Y%.4f F%.1f", CurYPosition, FastFeed))
	mm.ReturnCode(rc)
	if (XInc ~= 0) then
		rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G%.1f X%.4f F%.1f", ProbeCode, CurXPosition + XInc, FastFeed))
		mm.ReturnCode(rc)
		rc = Probing.CheckProbe(1, ProbeCode); if not rc then; do return end; end
		rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G%.1f Y%.4f F%.1f", ProbeCode, ProbeTo, FastFeed))
		mm.ReturnCode(rc)
		rc = Probing.CheckProbe(0, ProbeCode); if not rc then; do return end; end
		local ProbePoint = mc.mcCntlGetPoundVar(inst, mc.SV_PROBE_POS_Y)
		local RetractPoint = ProbePoint - YBackOff
		rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G1 Y%.4f F%.1f", RetractPoint, FastFeed))
		mm.ReturnCode(rc)
		--Measure
		rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G%.1f Y%.4f F%.1f", ProbeCode, ProbeTo, SlowFeed))
		mm.ReturnCode(rc)
		rc = Probing.CheckProbe(0, ProbeCode); if not rc then; do return end; end
		MeasPointY2ABS = mc.mcCntlGetPoundVar(inst, mc.SV_PROBE_POS_Y) + YProbeRad + YOffset
		MeasPointY2MACH = mc.mcCntlGetPoundVar(inst,mc.SV_PROBE_MACH_POS_Y) + YProbeRad + YOffset
		rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G01 Y%.4f F%.1f", CurYPosition, FastFeed))
		mm.ReturnCode(rc)
		rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G01 X%.4f F%.1f", CurXPosition, FastFeed))
		mm.ReturnCode(rc)
	end
	
	------------- Calculate and set offset/vars -------------
	
	if (YInc == 0) then
		--Assume 90 degree corner
		local PosErrorX = MeasPointX1ABS - XPos
		local PosErrorY = MeasPointY1ABS - YPos
		
		mc.mcCntlSetPoundVar(inst, 131, MeasPointX1MACH)
		mc.mcCntlSetPoundVar(inst, 141, MeasPointX1ABS)
		mc.mcCntlSetPoundVar(inst, 132, MeasPointY1MACH)
		mc.mcCntlSetPoundVar(inst, 142, MeasPointY1ABS)
		mc.mcCntlSetPoundVar(inst, 135, PosErrorX)
		mc.mcCntlSetPoundVar(inst, 136, PosErrorY)
	else
		--Calculate angles and intercept from multi point measurement
		local XMachShift = MeasPointX1MACH - MeasPointX1ABS
		local YMachShift = MeasPointY1MACH - MeasPointY1ABS
		
        local V1X = MeasPointX1ABS
        local V1i = MeasPointX2ABS - MeasPointX1ABS
        local V1Y = CurYPosition
        local V1j = YInc

        local V2X = CurXPosition
        local V2i = XInc
        local V2Y = MeasPointY1ABS
        local V2j = MeasPointY2ABS - MeasPointY1ABS
        
        local XCornerABS, YCornerABS
        XCornerABS, YCornerABS = Probing.VectorInt2D(V1X, V1i, V1Y, V1j, V2X, V2i, V2Y, V2j)
        local XCornerMACH = XCornerABS + XMachShift
        local YCornerMACH = YCornerABS + YMachShift
        local PosErrorX = XCornerABS - XPos
        local PosErrorY = YCornerABS - YPos
        
        local CornerAngle = Probing.VectorAngle2D(V1i, V1j, V2i, V2j)
        local XAngle = Probing.VectorAngle2D(V1i, V1j, 0, V1j)
		if (V1j < 0) and (V1i < 0) and (XAngle > 0) then
			XAngle = -XAngle
		elseif (V1j > 0) and (V1i > 0) and (XAngle > 0) then
			XAngle = -XAngle
		end
        local YAngle = Probing.VectorAngle2D(V2i, V2j, V2i, 0)
		if (V2i < 0) and (V2j > 0) and (YAngle > 0) then
			YAngle = -YAngle
		elseif (V2i > 0) and (V2j < 0) and (YAngle > 0) then
			YAngle = -YAngle
		end
        local AngleError = CornerAngle - 90

		mc.mcCntlSetPoundVar(inst, 145, XAngle)
		mc.mcCntlSetPoundVar(inst, 146, YAngle)

		mc.mcCntlSetPoundVar(inst, 144, CornerAngle)
		mc.mcCntlSetPoundVar(inst, 138, AngleError)

		mc.mcCntlSetPoundVar(inst, 141, XCornerABS)
		mc.mcCntlSetPoundVar(inst, 131, XCornerMACH)
		mc.mcCntlSetPoundVar(inst, 142, YCornerABS)
		mc.mcCntlSetPoundVar(inst, 132, YCornerMACH)
		mc.mcCntlSetPoundVar(inst, 135, PosErrorX)
		mc.mcCntlSetPoundVar(inst, 136, PosErrorY)
	end
	
	if (SetWork == 1) then
		local XVal = mc.mcCntlGetPoundVar(inst, 131)
		local YVal = mc.mcCntlGetPoundVar(inst, 132)
		Probing.SetFixOffset(XVal, YVal, nil)
	end
	
	------------- Reset State ------------------------------------
	mc.mcCntlSetPoundVar(inst, mc.SV_FEEDRATE, CurFeed)
	mc.mcCntlSetPoundVar(inst, mc.SV_MOD_GROUP_1, CurFeedMode)
	mc.mcCntlSetPoundVar(inst, mc.SV_MOD_GROUP_3, CurAbsMode)
end

function Probing.ExternalCorner(xpos, ypos, xinc, yinc, work)
	local inst = mc.mcGetInstance()
	------------- Errors -------------
	if (xpos == nil) then
		mc.mcCntlSetLastError(inst, "Probe: X position not input")
		do return end
	end
	if (ypos == nil) then
		mc.mcCntlSetLastError(inst, "Probe: Y position not input")
		do return end
	end
	if (xinc ~= nil) and (yinc == nil) then
		yinc = xinc
	elseif (yinc ~= nil) and (xinc == nil) then
		xinc = yinc
	end
	
	------------- Define Vars -------------
	Probing.NilVars(100, 150)
	local XPos = tonumber(xpos)
	local YPos = tonumber(ypos)
	local XInc = tonumber(xinc)
	local YInc = tonumber(yinc)
	if (xinc == nil) then
		XInc = 0
		YInc = 0
	end
	
	local SetWork = tonumber(work)
	
	local MeasPointX1ABS
	local MeasPointX1MACH
	local MeasPointX2ABS
	local MeasPointX2MACH
	
	local MeasPointY1ABS
	local MeasPointY1MACH
	local MeasPointY2ABS
	local MeasPointY2MACH
	
	local ProbeRad = mc.mcProfileGetDouble(inst, "ProbingSettings", "Radius", 0.000)
	local XOffset = mc.mcProfileGetDouble(inst, "ProbingSettings", "XOffset", 0.000)
	local YOffset = mc.mcProfileGetDouble(inst, "ProbingSettings", "YOffset", 0.000)
	local OffsetNum = mc.mcProfileGetDouble(inst , "ProbingSettings", "OffsetNum", 0.000)
	local SlowFeed = mc.mcProfileGetDouble(inst , "ProbingSettings", "SlowFeed", 0.000)
	local FastFeed = mc.mcProfileGetDouble(inst , "ProbingSettings", "FastFeed", 0.000)
	local BackOff = mc.mcProfileGetDouble(inst , "ProbingSettings", "BackOff", 0.000)
	local OverShoot = mc.mcProfileGetDouble(inst , "ProbingSettings", "OverShoot", 0.000)
	local InPosZone = mc.mcProfileGetDouble(inst , "ProbingSettings", "InPosZone", 0.000)
	local ProbeCode = mc.mcProfileGetDouble(inst , "ProbingSettings", "GCode", 0.000)
	
	------------- Get current state -------------
	local CurFeed = mc.mcCntlGetPoundVar(inst, mc.SV_FEEDRATE)
	local CurZOffset = mc.mcCntlGetPoundVar(inst, mc.SV_ORIGIN_OFFSET_Z)
	local CurFeedMode = mc.mcCntlGetPoundVar(inst, mc.SV_MOD_GROUP_1)
	local CurAbsMode = mc.mcCntlGetPoundVar(inst, mc.SV_MOD_GROUP_3)
	local CurXPosition = mc.mcAxisGetPos(inst, mc.X_AXIS)
	local CurYPosition = mc.mcAxisGetPos(inst, mc.Y_AXIS)
	
	
	------------- Check Probe -------------
	rc = Probing.CheckProbe(1, ProbeCode); if not rc then; do return end; end
	
	------------- Check direction -------------
	if (CurXPosition > XPos) then
		XBackOff = -BackOff
		XOverShoot = -OverShoot
		XProbeRad = -ProbeRad
	else
		XBackOff = BackOff
		XOverShoot = OverShoot
		XProbeRad = ProbeRad
	end
	
	if (CurYPosition > YPos) then
		YBackOff = -BackOff
		YOverShoot = -OverShoot
		YProbeRad = -ProbeRad
	else
		YBackOff = BackOff
		YOverShoot = OverShoot
		YProbeRad = ProbeRad
	end
	
	------------- Calculate measurment start positions -------------
	local XMeasurePos = CurXPosition + (2 * (XPos - CurXPosition))
	local YMeasurePos = CurYPosition + (2 * (YPos - CurYPosition))
	
	------------- Probe X Surface -------------
	local ProbeTo = XPos + XOverShoot
	local rc = mc.mcCntlGcodeExecuteWait(inst, "G0 G90 G40 G80")
	mm.ReturnCode(rc)
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G%.1f Y%.4f F%.1f", ProbeCode, YMeasurePos, FastFeed))
	mm.ReturnCode(rc)
	rc = Probing.CheckProbe(1, ProbeCode); if not rc then; do return end; end
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G%.1f X%.4f F%.1f", ProbeCode, ProbeTo, FastFeed))
	mm.ReturnCode(rc)
	rc = Probing.CheckProbe(0, ProbeCode); if not rc then; do return end; end
	local ProbePoint = mc.mcCntlGetPoundVar(inst, mc.SV_PROBE_POS_X)
	local RetractPoint = ProbePoint - XBackOff
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G1 X%.4f F%.1f", RetractPoint, FastFeed))
	mm.ReturnCode(rc)
	--Measure
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G%.1f X%.4f F%.1f", ProbeCode, ProbeTo, SlowFeed))
	mm.ReturnCode(rc)
	rc = Probing.CheckProbe(0, ProbeCode); if not rc then; do return end; end
	MeasPointX1ABS = mc.mcCntlGetPoundVar(inst, mc.SV_PROBE_POS_X) + XProbeRad + XOffset
	MeasPointX1MACH = mc.mcCntlGetPoundVar(inst,mc.SV_PROBE_MACH_POS_X) + XProbeRad + XOffset
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G1 X%.4f F%.1f", CurXPosition, FastFeed))
	mm.ReturnCode(rc)
	if (YInc ~= 0) then
		rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G%.1f Y%.4f F%.1f", ProbeCode, YMeasurePos + YInc, FastFeed))
		mm.ReturnCode(rc)
		rc = Probing.CheckProbe(1, ProbeCode); if not rc then; do return end; end
		rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G%.1f X%.4f F%.1f", ProbeCode, ProbeTo, FastFeed))
		mm.ReturnCode(rc)
		rc = Probing.CheckProbe(0, ProbeCode); if not rc then; do return end; end
		local ProbePoint = mc.mcCntlGetPoundVar(inst, mc.SV_PROBE_POS_X)
		local RetractPoint = ProbePoint - XBackOff
		rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G1 X%.4f F%.1f", RetractPoint, FastFeed))
		mm.ReturnCode(rc)
		--Measure
		rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G%.1f X%.4f F%.1f", ProbeCode, ProbeTo, SlowFeed))
		mm.ReturnCode(rc)
		rc = Probing.CheckProbe(0, ProbeCode); if not rc then; do return end; end
		MeasPointX2ABS = mc.mcCntlGetPoundVar(inst, mc.SV_PROBE_POS_X) + XProbeRad + XOffset
		MeasPointX2MACH = mc.mcCntlGetPoundVar(inst,mc.SV_PROBE_MACH_POS_X) + XProbeRad + XOffset
		rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G1 X%.4f F%.1f", CurXPosition, FastFeed))
		mm.ReturnCode(rc)
		rc = Probing.CheckProbe(1, ProbeCode); if not rc then; do return end; end
	end
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G%.1f Y%.4f F%.1f", ProbeCode, CurYPosition, FastFeed))
	mm.ReturnCode(rc)
	rc = Probing.CheckProbe(1, ProbeCode); if not rc then; do return end; end
	
		------------- Probe Y Surface -------------
	local ProbeTo = YPos + YOverShoot
	rc = mc.mcCntlGcodeExecuteWait(inst, "G0 G90 G40 G80")
	mm.ReturnCode(rc)
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G%.1f X%.4f F%.1f", ProbeCode, XMeasurePos, FastFeed))
	mm.ReturnCode(rc)
	rc = Probing.CheckProbe(1, ProbeCode); if not rc then; do return end; end
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G%.1f Y%.4f F%.1f", ProbeCode, ProbeTo, FastFeed))
	mm.ReturnCode(rc)
	rc = Probing.CheckProbe(0, ProbeCode); if not rc then; do return end; end
	local ProbePoint = mc.mcCntlGetPoundVar(inst, mc.SV_PROBE_POS_Y)
	local RetractPoint = ProbePoint - YBackOff
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G1 Y%.4f F%.1f", RetractPoint, FastFeed))
	mm.ReturnCode(rc)
	--Measure
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G%.1f Y%.4f F%.1f", ProbeCode, ProbeTo, SlowFeed))
	mm.ReturnCode(rc)
	rc = Probing.CheckProbe(0, ProbeCode); if not rc then; do return end; end
	MeasPointY1ABS = mc.mcCntlGetPoundVar(inst, mc.SV_PROBE_POS_Y) + YProbeRad + YOffset
	MeasPointY1MACH = mc.mcCntlGetPoundVar(inst,mc.SV_PROBE_MACH_POS_Y) + YProbeRad + YOffset
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G1 Y%.4f F%.1f", CurYPosition, FastFeed))
	mm.ReturnCode(rc)
	rc = Probing.CheckProbe(1, ProbeCode); if not rc then; do return end; end
	if (XInc ~= 0) then
		rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G%.1f X%.4f F%.1f", ProbeCode, XMeasurePos + XInc, FastFeed))
		mm.ReturnCode(rc)
		rc = Probing.CheckProbe(1, ProbeCode); if not rc then; do return end; end
		rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G%.1f Y%.4f F%.1f", ProbeCode, ProbeTo, FastFeed))
		mm.ReturnCode(rc)
		rc = Probing.CheckProbe(0, ProbeCode); if not rc then; do return end; end
		local ProbePoint = mc.mcCntlGetPoundVar(inst, mc.SV_PROBE_POS_Y)
		local RetractPoint = ProbePoint - YBackOff
		rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G1 Y%.4f F%.1f", RetractPoint, FastFeed))
		mm.ReturnCode(rc)
		--Measure
		rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G%.1f Y%.4f F%.1f", ProbeCode, ProbeTo, SlowFeed))
		mm.ReturnCode(rc)
		rc = Probing.CheckProbe(0, ProbeCode); if not rc then; do return end; end
		MeasPointY2ABS = mc.mcCntlGetPoundVar(inst, mc.SV_PROBE_POS_Y) + YProbeRad + YOffset
		MeasPointY2MACH = mc.mcCntlGetPoundVar(inst,mc.SV_PROBE_MACH_POS_Y) + YProbeRad + YOffset
		rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G1 Y%.4f F%.1f", CurYPosition, FastFeed))
		mm.ReturnCode(rc)
		rc = Probing.CheckProbe(1, ProbeCode); if not rc then; do return end; end
	end
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G%.1f X%.4f F%.1f", ProbeCode, CurXPosition, FastFeed))
	mm.ReturnCode(rc)
	rc = Probing.CheckProbe(1, ProbeCode); if not rc then; do return end; end
	
	------------- Calculate and set offset/vars -------------
	
	if (YInc == 0) then
		--Assume 90 degree corner
		local PosErrorX = MeasPointX1ABS - XPos
		local PosErrorY = MeasPointY1ABS - YPos
		
		mc.mcCntlSetPoundVar(inst, 131, MeasPointX1MACH)
		mc.mcCntlSetPoundVar(inst, 141, MeasPointX1ABS)
		mc.mcCntlSetPoundVar(inst, 132, MeasPointY1MACH)
		mc.mcCntlSetPoundVar(inst, 142, MeasPointY1ABS)
		mc.mcCntlSetPoundVar(inst, 135, PosErrorX)
		mc.mcCntlSetPoundVar(inst, 136, PosErrorY)
		
	else
		--Calculate angles and intercept from multi point measurement
		local XMachShift = MeasPointX1MACH - MeasPointX1ABS
		local YMachShift = MeasPointY1MACH - MeasPointY1ABS
		
        local V1X = MeasPointX1ABS
        local V1i = MeasPointX2ABS - MeasPointX1ABS
        local V1Y = CurYPosition
        local V1j = YInc

        local V2X = CurXPosition
        local V2i = XInc
        local V2Y = MeasPointY1ABS
        local V2j = MeasPointY2ABS - MeasPointY1ABS
        
        local XCornerABS, YCornerABS
        XCornerABS, YCornerABS = Probing.VectorInt2D(V1X, V1i, V1Y, V1j, V2X, V2i, V2Y, V2j)
        local XCornerMACH = XCornerABS + XMachShift
        local YCornerMACH = YCornerABS + YMachShift
        local PosErrorX = XCornerABS - XPos
        local PosErrorY = YCornerABS - YPos
        
        local CornerAngle = Probing.VectorAngle2D(V1i, V1j, V2i, V2j)
        local XAngle = Probing.VectorAngle2D(V1i, V1j, 0, V1j)
		if (V1j < 0) and (V1i < 0) and (XAngle > 0) then
			XAngle = -XAngle
		elseif (V1j > 0) and (V1i > 0) and (XAngle > 0) then
			XAngle = -XAngle
		end
        local YAngle = Probing.VectorAngle2D(V2i, V2j, V2i, 0)
		if (V2i < 0) and (V2j > 0) and (YAngle > 0) then
			YAngle = -YAngle
		elseif (V2i > 0) and (V2j < 0) and (YAngle > 0) then
			YAngle = -YAngle
		end
        local AngleError = CornerAngle - 90

		mc.mcCntlSetPoundVar(inst, 145, XAngle)
		mc.mcCntlSetPoundVar(inst, 146, YAngle)

		mc.mcCntlSetPoundVar(inst, 144, CornerAngle)
		mc.mcCntlSetPoundVar(inst, 138, AngleError)

		mc.mcCntlSetPoundVar(inst, 141, XCornerABS)
		mc.mcCntlSetPoundVar(inst, 131, XCornerMACH)
		mc.mcCntlSetPoundVar(inst, 142, YCornerABS)
		mc.mcCntlSetPoundVar(inst, 132, YCornerMACH)
		mc.mcCntlSetPoundVar(inst, 135, PosErrorX)
		mc.mcCntlSetPoundVar(inst, 136, PosErrorY)
	end
	
	if (SetWork == 1) then
		local XVal = mc.mcCntlGetPoundVar(inst, 131)
		local YVal = mc.mcCntlGetPoundVar(inst, 132)
		Probing.SetFixOffset(XVal, YVal, nil)
	end
	
	------------- Reset State ------------------------------------
	mc.mcCntlSetPoundVar(inst, mc.SV_FEEDRATE, CurFeed)
	mc.mcCntlSetPoundVar(inst, mc.SV_MOD_GROUP_1, CurFeedMode)
	mc.mcCntlSetPoundVar(inst, mc.SV_MOD_GROUP_3, CurAbsMode)
end

function Probing.InsideCenteringX(width, work)
	local inst = mc.mcGetInstance()
	------------- Errors -------------
	if (width == nil) then
		mc.mcCntlSetLastError(inst, "Probe: X width not input")
		do return end
	end
	------------- Define Vars -------------
	Probing.NilVars(100, 150)
	local XWidth = tonumber(width)
	
	local SetWork = tonumber(work)
	
	local ProbeRad = mc.mcProfileGetDouble(inst, "ProbingSettings", "Radius", 0.000)
	local XOffset = mc.mcProfileGetDouble(inst, "ProbingSettings", "XOffset", 0.000)
	local YOffset = mc.mcProfileGetDouble(inst, "ProbingSettings", "YOffset", 0.000)
	local OffsetNum = mc.mcProfileGetDouble(inst , "ProbingSettings", "OffsetNum", 0.000)
	local SlowFeed = mc.mcProfileGetDouble(inst , "ProbingSettings", "SlowFeed", 0.000)
	local FastFeed = mc.mcProfileGetDouble(inst , "ProbingSettings", "FastFeed", 0.000)
	local BackOff = mc.mcProfileGetDouble(inst , "ProbingSettings", "BackOff", 0.000)
	local OverShoot = mc.mcProfileGetDouble(inst , "ProbingSettings", "OverShoot", 0.000)
	local InPosZone = mc.mcProfileGetDouble(inst , "ProbingSettings", "InPosZone", 0.000)
	local ProbeCode = mc.mcProfileGetDouble(inst , "ProbingSettings", "GCode", 0.000)
	
	------------- Get current state -------------
	local CurFeed = mc.mcCntlGetPoundVar(inst, mc.SV_FEEDRATE)
	local CurZOffset = mc.mcCntlGetPoundVar(inst, mc.SV_ORIGIN_OFFSET_Z)
	local CurFeedMode = mc.mcCntlGetPoundVar(inst, mc.SV_MOD_GROUP_1)
	local CurAbsMode = mc.mcCntlGetPoundVar(inst, mc.SV_MOD_GROUP_3)
	local CurPosition = mc.mcAxisGetPos(inst, mc.X_AXIS)
	
	------------- Check Probe -------------
	rc = Probing.CheckProbe(1, ProbeCode); if not rc then; do return end; end
	
	------------- Probe Surface 1 -------------
	local ProbeTo = CurPosition + (XWidth / 2) + OverShoot
	local rc = mc.mcCntlGcodeExecuteWait(inst, "G0 G90 G40 G80")
	mm.ReturnCode(rc)
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G%.1f X%.4f F%.1f", ProbeCode, ProbeTo, FastFeed))
	mm.ReturnCode(rc)
	rc = Probing.CheckProbe(0, ProbeCode); if not rc then; do return end; end
	local ProbePoint = mc.mcCntlGetPoundVar(inst, mc.SV_PROBE_POS_X)
	local RetractPoint = ProbePoint - BackOff
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G1 X%.4f F%.1f", RetractPoint, FastFeed))
	mm.ReturnCode(rc)
	--Measure
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G%.1f X%.4f F%.1f", ProbeCode, ProbeTo, SlowFeed))
	mm.ReturnCode(rc)
	rc = Probing.CheckProbe(0, ProbeCode); if not rc then; do return end; end
	local MeasPoint1ABS = mc.mcCntlGetPoundVar(inst, mc.SV_PROBE_POS_X)
	local MeasPoint1MACH = mc.mcCntlGetPoundVar(inst,mc.SV_PROBE_MACH_POS_X)
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G1 X%.4f F%.1f", CurPosition, FastFeed))
	mm.ReturnCode(rc)
	
	------------- Probe Surface 2 -------------
	local ProbeTo = CurPosition - (XWidth / 2) - OverShoot
	rc = mc.mcCntlGcodeExecuteWait(inst, "G0 G90 G40 G80")
	mm.ReturnCode(rc)
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G%.1f X%.4f F%.1f", ProbeCode, ProbeTo, FastFeed))
	mm.ReturnCode(rc)
	rc = Probing.CheckProbe(0, ProbeCode); if not rc then; do return end; end
	local ProbePoint = mc.mcCntlGetPoundVar(inst, mc.SV_PROBE_POS_X)
	local RetractPoint = ProbePoint + BackOff
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G1 X%.4f F%.1f", RetractPoint, FastFeed))
	mm.ReturnCode(rc)
	--Measure
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G%.1f X%.4f F%.1f", ProbeCode, ProbeTo, SlowFeed))
	mm.ReturnCode(rc)
	rc = Probing.CheckProbe(0, ProbeCode); if not rc then; do return end; end
	local MeasPoint2ABS = mc.mcCntlGetPoundVar(inst, mc.SV_PROBE_POS_X)
	local MeasPoint2MACH = mc.mcCntlGetPoundVar(inst,mc.SV_PROBE_MACH_POS_X)
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G1 X%.4f F%.1f", CurPosition, FastFeed))
	mm.ReturnCode(rc)
	
	------------- Calculate and set offset/vars -------------
	MeasPoint1ABS = MeasPoint1ABS + ProbeRad + XOffset
	MeasPoint1MACH = MeasPoint1MACH + ProbeRad + XOffset
	MeasPoint2ABS = MeasPoint2ABS - ProbeRad + XOffset
	MeasPoint2MACH = MeasPoint2MACH - ProbeRad + XOffset
	local MeasPointABS = (MeasPoint1ABS + MeasPoint2ABS) / 2
	local MeasPointMACH = (MeasPoint1MACH + MeasPoint2MACH) / 2
	local PosError = MeasPointABS - CurPosition
	local Width = MeasPoint1ABS - MeasPoint2ABS
	local WidthError = Width - XWidth
	
	mc.mcCntlSetPoundVar(inst, 131, MeasPointMACH)
	mc.mcCntlSetPoundVar(inst, 141, MeasPointABS)
	mc.mcCntlSetPoundVar(inst, 144, Width)
	mc.mcCntlSetPoundVar(inst, 135, PosError)
	mc.mcCntlSetPoundVar(inst, 138, WidthError)
	
	if (SetWork == 1) then
		Probing.SetFixOffset(MeasPointMACH, nil, nil)
	end
	
	------------- Reset State ------------------------------------
	mc.mcCntlSetPoundVar(inst, mc.SV_FEEDRATE, CurFeed)
	mc.mcCntlSetPoundVar(inst, mc.SV_MOD_GROUP_1, CurFeedMode)
	mc.mcCntlSetPoundVar(inst, mc.SV_MOD_GROUP_3, CurAbsMode)
end

function Probing.OutsideCenteringX(width, approach, zpos, work)
	local inst = mc.mcGetInstance()
	------------- Errors -------------
	if (width == nil) then
		mc.mcCntlSetLastError(inst, "Probe: X width not input")
		do return end
	end
	if (approach == nil) then
		mc.mcCntlSetLastError(inst, "Probe: Approach not input")
		do return end
	end
	if (zpos == nil) then
		mc.mcCntlSetLastError(inst, "Probe: Z measure position not input")
		do return end
	end
	
	------------- Define Vars -------------
	Probing.NilVars(100, 150)
	local XWidth = tonumber(width)
	local Approach = tonumber(approach)
	local ZLevel = tonumber(zpos)
	
	local SetWork = tonumber(work)
	
	local ProbeRad = mc.mcProfileGetDouble(inst, "ProbingSettings", "Radius", 0.000)
	local XOffset = mc.mcProfileGetDouble(inst, "ProbingSettings", "XOffset", 0.000)
	local YOffset = mc.mcProfileGetDouble(inst, "ProbingSettings", "YOffset", 0.000)
	local OffsetNum = mc.mcProfileGetDouble(inst , "ProbingSettings", "OffsetNum", 0.000)
	local SlowFeed = mc.mcProfileGetDouble(inst , "ProbingSettings", "SlowFeed", 0.000)
	local FastFeed = mc.mcProfileGetDouble(inst , "ProbingSettings", "FastFeed", 0.000)
	local BackOff = mc.mcProfileGetDouble(inst , "ProbingSettings", "BackOff", 0.000)
	local OverShoot = mc.mcProfileGetDouble(inst , "ProbingSettings", "OverShoot", 0.000)
	local InPosZone = mc.mcProfileGetDouble(inst , "ProbingSettings", "InPosZone", 0.000)
	local ProbeCode = mc.mcProfileGetDouble(inst , "ProbingSettings", "GCode", 0.000)
	
	------------- Get current state -------------
	local CurFeed = mc.mcCntlGetPoundVar(inst, mc.SV_FEEDRATE)
	local CurZOffset = mc.mcCntlGetPoundVar(inst, mc.SV_ORIGIN_OFFSET_Z)
	local CurFeedMode = mc.mcCntlGetPoundVar(inst, mc.SV_MOD_GROUP_1)
	local CurAbsMode = mc.mcCntlGetPoundVar(inst, mc.SV_MOD_GROUP_3)
	local CurPosition = mc.mcAxisGetPos(inst, mc.X_AXIS)
	local CurZPosition = mc.mcAxisGetPos(inst, mc.Z_AXIS)
	
	------------- Check Probe -------------
	rc = Probing.CheckProbe(1, ProbeCode); if not rc then; do return end; end
	
	------------- Probe Surface 1 -------------
	local ProbeTo = CurPosition + (XWidth / 2) - OverShoot
	local RetractPoint
	local rc = mc.mcCntlGcodeExecuteWait(inst, "G0 G90 G40 G80")
	mm.ReturnCode(rc)
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G43 H%.0f", OffsetNum))
	mm.ReturnCode(rc)
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G%.1f X%.4f F%.1f", ProbeCode, ProbeTo + Approach + OverShoot, FastFeed))
	mm.ReturnCode(rc)
	rc = Probing.CheckProbe(1, ProbeCode); if not rc then; do return end; end
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G%.1f Z%.4f F%.1f", ProbeCode, ZLevel, FastFeed))
	mm.ReturnCode(rc)
	rc = Probing.CheckProbe(1, ProbeCode); if not rc then; do return end; end
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G%.1f X%.4f F%.1f", ProbeCode, ProbeTo, FastFeed))
	mm.ReturnCode(rc)
	rc = Probing.CheckProbe(0, ProbeCode); if not rc then; do return end; end
	local ProbePoint = mc.mcCntlGetPoundVar(inst, mc.SV_PROBE_POS_X)
	if ((ProbeTo + Approach + OverShoot) < ProbeTo) then
		RetractPoint = ProbePoint - BackOff
	else
		RetractPoint = ProbePoint + BackOff
	end
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G1 X%.4f F%.1f", RetractPoint, FastFeed))
	mm.ReturnCode(rc)
	--Measure
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G%.1f X%.4f F%.1f", ProbeCode, ProbeTo, SlowFeed))
	mm.ReturnCode(rc)
	rc = Probing.CheckProbe(0, ProbeCode); if not rc then; do return end; end
	local MeasPoint1ABS = mc.mcCntlGetPoundVar(inst, mc.SV_PROBE_POS_X)
	local MeasPoint1MACH = mc.mcCntlGetPoundVar(inst,mc.SV_PROBE_MACH_POS_X)
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G1 Z%.4f F%.1f", CurZPosition, FastFeed))
	mm.ReturnCode(rc)
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G1 X%.4f F%.1f", CurPosition, FastFeed))
	mm.ReturnCode(rc)
	if ((ProbeTo + Approach) < ProbeTo) then
		MeasPoint1ABS = MeasPoint1ABS + ProbeRad + XOffset
		MeasPoint1MACH = MeasPoint1MACH + ProbeRad + XOffset
	else
		MeasPoint1ABS = MeasPoint1ABS - ProbeRad + XOffset
		MeasPoint1MACH = MeasPoint1MACH - ProbeRad + XOffset
	end
	
	------------- Probe Surface 2 -------------
	local ProbeTo = CurPosition - (XWidth / 2) + OverShoot
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G%.1f X%.4f F%.1f", ProbeCode, ProbeTo - Approach, FastFeed))
	mm.ReturnCode(rc)
	rc = Probing.CheckProbe(1, ProbeCode); if not rc then; do return end; end
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G%.1f Z%.4f F%.1f", ProbeCode, ZLevel, FastFeed))
	mm.ReturnCode(rc)
	rc = Probing.CheckProbe(1, ProbeCode); if not rc then; do return end; end
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G%.1f X%.4f F%.1f", ProbeCode, ProbeTo, FastFeed))
	mm.ReturnCode(rc)
	rc = Probing.CheckProbe(0, ProbeCode); if not rc then; do return end; end
	local ProbePoint = mc.mcCntlGetPoundVar(inst, mc.SV_PROBE_POS_X)
	if ((ProbeTo - Approach) > ProbeTo) then
		RetractPoint = ProbePoint + BackOff
	else
		RetractPoint = ProbePoint - BackOff
	end
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G1 X%.4f F%.1f", RetractPoint, FastFeed))
	mm.ReturnCode(rc)
	--Measure
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G%.1f X%.4f F%.1f", ProbeCode, ProbeTo, SlowFeed))
	mm.ReturnCode(rc)
	rc = Probing.CheckProbe(0, ProbeCode); if not rc then; do return end; end
	local MeasPoint2ABS = mc.mcCntlGetPoundVar(inst, mc.SV_PROBE_POS_X)
	local MeasPoint2MACH = mc.mcCntlGetPoundVar(inst,mc.SV_PROBE_MACH_POS_X)
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G1 Z%.4f F%.1f", CurZPosition, FastFeed))
	mm.ReturnCode(rc)
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G1 X%.4f F%.1f", CurPosition, FastFeed))
	mm.ReturnCode(rc)
	if ((ProbeTo - Approach) > ProbeTo) then
		MeasPoint2ABS = MeasPoint2ABS - ProbeRad + XOffset
		MeasPoint2MACH = MeasPoint2MACH - ProbeRad + XOffset
	else
		MeasPoint2ABS = MeasPoint2ABS + ProbeRad + XOffset
		MeasPoint2MACH = MeasPoint2MACH + ProbeRad + XOffset
	end
	
	------------- Calculate and set offset/vars -------------
	local MeasPointABS = (MeasPoint1ABS + MeasPoint2ABS) / 2
	local MeasPointMACH = (MeasPoint1MACH + MeasPoint2MACH) / 2
	local PosError = MeasPointABS - CurPosition
	local Width = MeasPoint1ABS - MeasPoint2ABS
	local WidthError = Width - XWidth
	
	mc.mcCntlSetPoundVar(inst, 131, MeasPointMACH)
	mc.mcCntlSetPoundVar(inst, 141, MeasPointABS)
	mc.mcCntlSetPoundVar(inst, 144, Width)
	mc.mcCntlSetPoundVar(inst, 135, PosError)
	mc.mcCntlSetPoundVar(inst, 138, WidthError)
	
	if (SetWork == 1) then
		Probing.SetFixOffset(MeasPointMACH, nil, nil)
	end
	
	------------- Reset State ------------------------------------
	mc.mcCntlSetPoundVar(inst, mc.SV_FEEDRATE, CurFeed)
	mc.mcCntlSetPoundVar(inst, mc.SV_MOD_GROUP_1, CurFeedMode)
	mc.mcCntlSetPoundVar(inst, mc.SV_MOD_GROUP_3, CurAbsMode)
end

function Probing.InsideCenteringY(width, work)
	local inst = mc.mcGetInstance()
	------------- Errors -------------
	if (width == nil) then
		mc.mcCntlSetLastError(inst, "Probe: Y width not input")
		do return end
	end
	
	------------- Define Vars -------------
	Probing.NilVars(100, 150)
	local YWidth = tonumber(width)
	
	local SetWork = tonumber(work)
	
	local ProbeRad = mc.mcProfileGetDouble(inst, "ProbingSettings", "Radius", 0.000)
	local XOffset = mc.mcProfileGetDouble(inst, "ProbingSettings", "XOffset", 0.000)
	local YOffset = mc.mcProfileGetDouble(inst, "ProbingSettings", "YOffset", 0.000)
	local OffsetNum = mc.mcProfileGetDouble(inst , "ProbingSettings", "OffsetNum", 0.000)
	local SlowFeed = mc.mcProfileGetDouble(inst , "ProbingSettings", "SlowFeed", 0.000)
	local FastFeed = mc.mcProfileGetDouble(inst , "ProbingSettings", "FastFeed", 0.000)
	local BackOff = mc.mcProfileGetDouble(inst , "ProbingSettings", "BackOff", 0.000)
	local OverShoot = mc.mcProfileGetDouble(inst , "ProbingSettings", "OverShoot", 0.000)
	local InPosZone = mc.mcProfileGetDouble(inst , "ProbingSettings", "InPosZone", 0.000)
	local ProbeCode = mc.mcProfileGetDouble(inst , "ProbingSettings", "GCode", 0.000)
	
	------------- Get current state -------------
	local CurFeed = mc.mcCntlGetPoundVar(inst, mc.SV_FEEDRATE)
	local CurZOffset = mc.mcCntlGetPoundVar(inst, mc.SV_ORIGIN_OFFSET_Z)
	local CurFeedMode = mc.mcCntlGetPoundVar(inst, mc.SV_MOD_GROUP_1)
	local CurAbsMode = mc.mcCntlGetPoundVar(inst, mc.SV_MOD_GROUP_3)
	local CurPosition = mc.mcAxisGetPos(inst, mc.Y_AXIS)
	
	------------- Check Probe -------------
	rc = Probing.CheckProbe(1, ProbeCode); if not rc then; do return end; end
	
	------------- Probe Surface 1 -------------
	local ProbeTo = CurPosition + (YWidth / 2) + OverShoot
	local rc = mc.mcCntlGcodeExecuteWait(inst, "G0 G90 G40 G80")
	mm.ReturnCode(rc)
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G%.1f Y%.4f F%.1f", ProbeCode, ProbeTo, FastFeed))
	mm.ReturnCode(rc)
	rc = Probing.CheckProbe(0, ProbeCode); if not rc then; do return end; end
	local ProbePoint = mc.mcCntlGetPoundVar(inst, mc.SV_PROBE_POS_Y)
	local RetractPoint = ProbePoint - BackOff
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G1 Y%.4f F%.1f", RetractPoint, FastFeed))
	mm.ReturnCode(rc)
	--Measure
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G%.1f Y%.4f F%.1f", ProbeCode, ProbeTo, SlowFeed))
	mm.ReturnCode(rc)
	rc = Probing.CheckProbe(0, ProbeCode); if not rc then; do return end; end
	local MeasPoint1ABS = mc.mcCntlGetPoundVar(inst, mc.SV_PROBE_POS_Y)
	local MeasPoint1MACH = mc.mcCntlGetPoundVar(inst,mc.SV_PROBE_MACH_POS_Y)
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G1 Y%.4f F%.1f", CurPosition, FastFeed))
	mm.ReturnCode(rc)
	
	------------- Probe Surface 2 -------------
	local ProbeTo = CurPosition - (YWidth / 2) - OverShoot
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G%.1f Y%.4f F%.1f", ProbeCode, ProbeTo, FastFeed))
	mm.ReturnCode(rc)
	rc = Probing.CheckProbe(0, ProbeCode); if not rc then; do return end; end
	local ProbePoint = mc.mcCntlGetPoundVar(inst, mc.SV_PROBE_POS_Y)
	local RetractPoint = ProbePoint + BackOff
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G1 Y%.4f F%.1f", RetractPoint, FastFeed))
	mm.ReturnCode(rc)
	--Measure
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G%.1f Y%.4f F%.1f", ProbeCode, ProbeTo, SlowFeed))
	mm.ReturnCode(rc)
	rc = Probing.CheckProbe(0, ProbeCode); if not rc then; do return end; end
	local MeasPoint2ABS = mc.mcCntlGetPoundVar(inst, mc.SV_PROBE_POS_Y)
	local MeasPoint2MACH = mc.mcCntlGetPoundVar(inst,mc.SV_PROBE_MACH_POS_Y)
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G1 Y%.4f F%.1f", CurPosition, FastFeed))
	mm.ReturnCode(rc)
	
	------------- Calculate and set offset/vars -------------
	MeasPoint1ABS = MeasPoint1ABS + ProbeRad + YOffset
	MeasPoint1MACH = MeasPoint1MACH + ProbeRad + YOffset
	MeasPoint2ABS = MeasPoint2ABS - ProbeRad + YOffset
	MeasPoint2MACH = MeasPoint2MACH - ProbeRad + YOffset
	local MeasPointABS = (MeasPoint1ABS + MeasPoint2ABS) / 2
	local MeasPointMACH = (MeasPoint1MACH + MeasPoint2MACH) / 2
	local PosError = MeasPointABS - CurPosition
	local Width = MeasPoint1ABS - MeasPoint2ABS
	local WidthError = Width - YWidth
	
	mc.mcCntlSetPoundVar(inst, 132, MeasPointMACH)
	mc.mcCntlSetPoundVar(inst, 142, MeasPointABS)
	mc.mcCntlSetPoundVar(inst, 144, Width)
	mc.mcCntlSetPoundVar(inst, 136, PosError)
	mc.mcCntlSetPoundVar(inst, 138, WidthError)
	
	if (SetWork == 1) then
		Probing.SetFixOffset(nil, MeasPointMACH, nil)
	end
	
	------------- Reset State ------------------------------------
	mc.mcCntlSetPoundVar(inst, mc.SV_FEEDRATE, CurFeed)
	mc.mcCntlSetPoundVar(inst, mc.SV_MOD_GROUP_1, CurFeedMode)
	mc.mcCntlSetPoundVar(inst, mc.SV_MOD_GROUP_3, CurAbsMode)
end

function Probing.OutsideCenteringY(width, approach, zpos, work) 
	local inst = mc.mcGetInstance()
	------------- Errors -------------
	if (width == nil) then
		mc.mcCntlSetLastError(inst, "Probe: Y width not input")
		do return end
	end
	if (approach == nil) then
		mc.mcCntlSetLastError(inst, "Probe: Approach not input")
		do return end
	end
	if (zpos == nil) then
		mc.mcCntlSetLastError(inst, "Probe: Z measure position not input")
		do return end
	end
	
	------------- Define Vars -------------
	Probing.NilVars(100, 150)
	local YWidth = tonumber(width)
	local Approach = tonumber(approach)
	local ZLevel = tonumber(zpos)
	
	local SetWork = tonumber(work)
	
	local ProbeRad = mc.mcProfileGetDouble(inst, "ProbingSettings", "Radius", 0.000)
	local XOffset = mc.mcProfileGetDouble(inst, "ProbingSettings", "XOffset", 0.000)
	local YOffset = mc.mcProfileGetDouble(inst, "ProbingSettings", "YOffset", 0.000)
	local OffsetNum = mc.mcProfileGetDouble(inst , "ProbingSettings", "OffsetNum", 0.000)
	local SlowFeed = mc.mcProfileGetDouble(inst , "ProbingSettings", "SlowFeed", 0.000)
	local FastFeed = mc.mcProfileGetDouble(inst , "ProbingSettings", "FastFeed", 0.000)
	local BackOff = mc.mcProfileGetDouble(inst , "ProbingSettings", "BackOff", 0.000)
	local OverShoot = mc.mcProfileGetDouble(inst , "ProbingSettings", "OverShoot", 0.000)
	local InPosZone = mc.mcProfileGetDouble(inst , "ProbingSettings", "InPosZone", 0.000)
	local ProbeCode = mc.mcProfileGetDouble(inst , "ProbingSettings", "GCode", 0.000)
	
	------------- Get current state -------------
	local CurFeed = mc.mcCntlGetPoundVar(inst, mc.SV_FEEDRATE)
	local CurZOffset = mc.mcCntlGetPoundVar(inst, mc.SV_ORIGIN_OFFSET_Z)
	local CurFeedMode = mc.mcCntlGetPoundVar(inst, mc.SV_MOD_GROUP_1)
	local CurAbsMode = mc.mcCntlGetPoundVar(inst, mc.SV_MOD_GROUP_3)
	local CurPosition = mc.mcAxisGetPos(inst, mc.Y_AXIS)
	local CurZPosition = mc.mcAxisGetPos(inst, mc.Z_AXIS)
	
	------------- Check Probe -------------
	rc = Probing.CheckProbe(1, ProbeCode); if not rc then; do return end; end
	
	------------- Probe Surface 1 -------------
	local ProbeTo = CurPosition + (YWidth / 2) - OverShoot
	local RetractPoint
	local rc = mc.mcCntlGcodeExecuteWait(inst, "G0 G90 G40 G80")
	mm.ReturnCode(rc)
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G43 H%.0f", OffsetNum))
	mm.ReturnCode(rc)
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G%.1f Y%.4f F%.1f", ProbeCode, ProbeTo + Approach + OverShoot, FastFeed))
	mm.ReturnCode(rc)
	rc = Probing.CheckProbe(1, ProbeCode); if not rc then; do return end; end
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G%.1f Z%.4f F%.1f", ProbeCode, ZLevel, FastFeed))
	mm.ReturnCode(rc)
	rc = Probing.CheckProbe(1, ProbeCode); if not rc then; do return end; end
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G%.1f Y%.4f F%.1f", ProbeCode, ProbeTo, FastFeed))
	mm.ReturnCode(rc)
	rc = Probing.CheckProbe(0, ProbeCode); if not rc then; do return end; end
	local ProbePoint = mc.mcCntlGetPoundVar(inst, mc.SV_PROBE_POS_Y)
	if ((ProbeTo + Approach) < ProbeTo) then
		RetractPoint = ProbePoint - BackOff
	else
		RetractPoint = ProbePoint + BackOff
	end
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G1 Y%.4f F%.1f", RetractPoint, FastFeed))
	mm.ReturnCode(rc)
	--Measure
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G%.1f Y%.4f F%.1f", ProbeCode, ProbeTo, SlowFeed))
	mm.ReturnCode(rc)
	rc = Probing.CheckProbe(0, ProbeCode); if not rc then; do return end; end
	local MeasPoint1ABS = mc.mcCntlGetPoundVar(inst, mc.SV_PROBE_POS_Y)
	local MeasPoint1MACH = mc.mcCntlGetPoundVar(inst,mc.SV_PROBE_MACH_POS_Y)
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G1 Z%.4f F%.1f", CurZPosition, FastFeed))
	mm.ReturnCode(rc)
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G1 Y%.4f F%.1f", CurPosition, FastFeed))
	mm.ReturnCode(rc)
	if ((ProbeTo + Approach) < ProbeTo) then
		MeasPoint1ABS = MeasPoint1ABS + ProbeRad + YOffset
		MeasPoint1MACH = MeasPoint1MACH + ProbeRad + YOffset
	else
		MeasPoint1ABS = MeasPoint1ABS - ProbeRad + YOffset
		MeasPoint1MACH = MeasPoint1MACH - ProbeRad + YOffset
	end
	
	------------- Probe Surface 2 -------------
	local ProbeTo = CurPosition - (YWidth / 2) + OverShoot
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G%.1f Y%.4f F%.1f", ProbeCode, ProbeTo - Approach, FastFeed))
	mm.ReturnCode(rc)
	rc = Probing.CheckProbe(1, ProbeCode); if not rc then; do return end; end
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G%.1f Z%.4f F%.1f", ProbeCode, ZLevel, FastFeed))
	mm.ReturnCode(rc)
	rc = Probing.CheckProbe(1, ProbeCode); if not rc then; do return end; end
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G%.1f Y%.4f F%.1f", ProbeCode, ProbeTo, FastFeed))
	mm.ReturnCode(rc)
	rc = Probing.CheckProbe(0, ProbeCode); if not rc then; do return end; end
	local ProbePoint = mc.mcCntlGetPoundVar(inst, mc.SV_PROBE_POS_Y)
	if ((ProbeTo - Approach) > ProbeTo) then
		RetractPoint = ProbePoint + BackOff
	else
		RetractPoint = ProbePoint - BackOff
	end
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G1 Y%.4f F%.1f", RetractPoint, FastFeed))
	mm.ReturnCode(rc)
	--Measure
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G%.1f Y%.4f F%.1f", ProbeCode, ProbeTo, SlowFeed))
	mm.ReturnCode(rc)
	rc = Probing.CheckProbe(0, ProbeCode); if not rc then; do return end; end
	local MeasPoint2ABS = mc.mcCntlGetPoundVar(inst, mc.SV_PROBE_POS_Y)
	local MeasPoint2MACH = mc.mcCntlGetPoundVar(inst,mc.SV_PROBE_MACH_POS_Y)
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G1 Z%.4f F%.1f", CurZPosition, FastFeed))
	mm.ReturnCode(rc)
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G1 Y%.4f F%.1f", CurPosition, FastFeed))
	mm.ReturnCode(rc)
	if ((ProbeTo - Approach) > ProbeTo) then
		MeasPoint2ABS = MeasPoint2ABS - ProbeRad + YOffset
		MeasPoint2MACH = MeasPoint2MACH - ProbeRad + YOffset
	else
		MeasPoint2ABS = MeasPoint2ABS + ProbeRad + YOffset
		MeasPoint2MACH = MeasPoint2MACH + ProbeRad + YOffset
	end
	
	------------- Calculate and set offset/vars -------------
	local MeasPointABS = (MeasPoint1ABS + MeasPoint2ABS) / 2
	local MeasPointMACH = (MeasPoint1MACH + MeasPoint2MACH) / 2
	local PosError = MeasPointABS - CurPosition
	local Width = MeasPoint1ABS - MeasPoint2ABS
	local WidthError = Width - YWidth
	
	mc.mcCntlSetPoundVar(inst, 132, MeasPointMACH)
	mc.mcCntlSetPoundVar(inst, 142, MeasPointABS)
	mc.mcCntlSetPoundVar(inst, 144, Width)
	mc.mcCntlSetPoundVar(inst, 136, PosError)
	mc.mcCntlSetPoundVar(inst, 138, WidthError)
	
	if (SetWork == 1) then
		Probing.SetFixOffset(nil, MeasPointMACH, nil)
	end
	
	------------- Reset State ------------------------------------
	mc.mcCntlSetPoundVar(inst, mc.SV_FEEDRATE, CurFeed)
	mc.mcCntlSetPoundVar(inst, mc.SV_MOD_GROUP_1, CurFeedMode)
	mc.mcCntlSetPoundVar(inst, mc.SV_MOD_GROUP_3, CurAbsMode)
end

function Probing.Bore(diam, work)
	local inst = mc.mcGetInstance()
	------------- Errors -------------
	if (diam == nil) then
		mc.mcCntlSetLastError(inst, "Probe: Bore diam not input")
		do return end
	end
	
	------------- Define Vars -------------
	Probing.NilVars(100, 150)
	local Diam = tonumber(diam)
	
	local SetWork = tonumber(work)
	
	local ProbeRad = mc.mcProfileGetDouble(inst, "ProbingSettings", "Radius", 0.000)
	local XOffset = mc.mcProfileGetDouble(inst, "ProbingSettings", "XOffset", 0.000)
	local YOffset = mc.mcProfileGetDouble(inst, "ProbingSettings", "YOffset", 0.000)
	local OffsetNum = mc.mcProfileGetDouble(inst , "ProbingSettings", "OffsetNum", 0.000)
	local SlowFeed = mc.mcProfileGetDouble(inst , "ProbingSettings", "SlowFeed", 0.000)
	local FastFeed = mc.mcProfileGetDouble(inst , "ProbingSettings", "FastFeed", 0.000)
	local BackOff = mc.mcProfileGetDouble(inst , "ProbingSettings", "BackOff", 0.000)
	local OverShoot = mc.mcProfileGetDouble(inst , "ProbingSettings", "OverShoot", 0.000)
	local InPosZone = mc.mcProfileGetDouble(inst , "ProbingSettings", "InPosZone", 0.000)
	local ProbeCode = mc.mcProfileGetDouble(inst , "ProbingSettings", "GCode", 0.000)
	
	------------- Get current state -------------
	local CurFeed = mc.mcCntlGetPoundVar(inst, mc.SV_FEEDRATE)
	local CurZOffset = mc.mcCntlGetPoundVar(inst, mc.SV_ORIGIN_OFFSET_Z)
	local CurFeedMode = mc.mcCntlGetPoundVar(inst, mc.SV_MOD_GROUP_1)
	local CurAbsMode = mc.mcCntlGetPoundVar(inst, mc.SV_MOD_GROUP_3)
	local CurXPosition = mc.mcAxisGetPos(inst, mc.X_AXIS)
	local CurYPosition = mc.mcAxisGetPos(inst, mc.Y_AXIS)
	
	------------- Check Probe -------------
	rc = Probing.CheckProbe(1, ProbeCode); if not rc then; do return end; end
	
	------------- Probing positions -------------
	local ProbeToXp = CurXPosition + (Diam / 2) + OverShoot
	local ProbeToXm = CurXPosition - (Diam / 2) - OverShoot
	local ProbeToYp = CurYPosition + (Diam / 2) + OverShoot
	local ProbeToYm = CurYPosition - (Diam / 2) - OverShoot
	
	------------- Probing sequence -------------
	local rc = mc.mcCntlGcodeExecuteWait(inst, "G0 G90 G40 G80")
	mm.ReturnCode(rc)
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G%.1f Y%.4f F%.1f", ProbeCode, ProbeToYp, FastFeed))
	mm.ReturnCode(rc)
	rc = Probing.CheckProbe(0, ProbeCode); if not rc then; do return end; end
	local ProbePointY1 = mc.mcCntlGetPoundVar(inst, mc.SV_PROBE_POS_Y)
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G1 Y%.4f F%.1f", CurYPosition, FastFeed))
	mm.ReturnCode(rc)
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G%.1f Y%.4f F%.1f", ProbeCode, ProbeToYm, FastFeed))
	mm.ReturnCode(rc)
	rc = Probing.CheckProbe(0, ProbeCode); if not rc then; do return end; end
	local ProbePointY2 = mc.mcCntlGetPoundVar(inst, mc.SV_PROBE_POS_Y)
	ProbePointY1 = ProbePointY1 + ProbeRad + YOffset
	ProbePointY2 = ProbePointY2 - ProbeRad + YOffset
	local YCenter = (ProbePointY1 + ProbePointY2) / 2
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G1 Y%.4f F%.1f", YCenter, FastFeed))
	mm.ReturnCode(rc)
	
	------------- Find X Center -------------
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G%.1f X%.4f F%.1f", ProbeCode, ProbeToXp, FastFeed))
	mm.ReturnCode(rc)
	rc = Probing.CheckProbe(0, ProbeCode); if not rc then; do return end; end
	local ProbePoint = mc.mcCntlGetPoundVar(inst, mc.SV_PROBE_POS_X)
	local RetractPoint = ProbePoint - BackOff
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G1 X%.4f F%.1f", RetractPoint, FastFeed))
	mm.ReturnCode(rc)
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G%.1f X%.4f F%.1f", ProbeCode, ProbeToXp, SlowFeed))
	mm.ReturnCode(rc)
	rc = Probing.CheckProbe(0, ProbeCode); if not rc then; do return end; end
	local MeasPointX1ABS = mc.mcCntlGetPoundVar(inst, mc.SV_PROBE_POS_X)
	local MeasPointX1MACH = mc.mcCntlGetPoundVar(inst,mc.SV_PROBE_MACH_POS_X)
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G1 X%.4f F%.1f", CurXPosition, FastFeed))
	mm.ReturnCode(rc)
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G%.1f X%.4f F%.1f", ProbeCode, ProbeToXm, FastFeed))
	mm.ReturnCode(rc)
	rc = Probing.CheckProbe(0, ProbeCode); if not rc then; do return end; end
	local ProbePoint = mc.mcCntlGetPoundVar(inst, mc.SV_PROBE_POS_X)
	local RetractPoint = ProbePoint + BackOff
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G1 X%.4f F%.1f", RetractPoint, FastFeed))
	mm.ReturnCode(rc)
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G%.1f X%.4f F%.1f", ProbeCode, ProbeToXm, SlowFeed))
	mm.ReturnCode(rc)
	rc = Probing.CheckProbe(0, ProbeCode); if not rc then; do return end; end
	local MeasPointX2ABS = mc.mcCntlGetPoundVar(inst, mc.SV_PROBE_POS_X)
	local MeasPointX2MACH = mc.mcCntlGetPoundVar(inst,mc.SV_PROBE_MACH_POS_X)
	
	------------- Calculate X Center -------------
	MeasPointX1ABS = MeasPointX1ABS + ProbeRad + XOffset
	MeasPointX1MACH = MeasPointX1MACH + ProbeRad + XOffset
	MeasPointX2ABS = MeasPointX2ABS - ProbeRad + XOffset
	MeasPointX2MACH = MeasPointX2MACH - ProbeRad + XOffset
	local CenterPointXABS = (MeasPointX1ABS + MeasPointX2ABS) / 2
	local CenterPointXMACH = (MeasPointX1MACH + MeasPointX2MACH) / 2
	
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G1 X%.4f F%.1f", CenterPointXABS, FastFeed))
	mm.ReturnCode(rc)
	
	------------- Find Y Center -------------
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G%.1f Y%.4f F%.1f", ProbeCode, ProbeToYp, FastFeed))
	mm.ReturnCode(rc)
	rc = Probing.CheckProbe(0, ProbeCode); if not rc then; do return end; end
	local ProbePoint = mc.mcCntlGetPoundVar(inst, mc.SV_PROBE_POS_Y)
	local RetractPoint = ProbePoint - BackOff
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G1 Y%.4f F%.1f", RetractPoint, FastFeed))
	mm.ReturnCode(rc)
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G%.1f Y%.4f F%.1f", ProbeCode, ProbeToYp, SlowFeed))
	mm.ReturnCode(rc)
	rc = Probing.CheckProbe(0, ProbeCode); if not rc then; do return end; end
	local MeasPointY1ABS = mc.mcCntlGetPoundVar(inst, mc.SV_PROBE_POS_Y)
	local MeasPointY1MACH = mc.mcCntlGetPoundVar(inst,mc.SV_PROBE_MACH_POS_Y)
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G1 Y%.4f F%.1f", CurYPosition, FastFeed))
	mm.ReturnCode(rc)
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G%.1f Y%.4f F%.1f", ProbeCode, ProbeToYm, FastFeed))
	mm.ReturnCode(rc)
	rc = Probing.CheckProbe(0, ProbeCode); if not rc then; do return end; end
	local ProbePoint = mc.mcCntlGetPoundVar(inst, mc.SV_PROBE_POS_Y)
	local RetractPoint = ProbePoint + BackOff
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G1 Y%.4f F%.1f", RetractPoint, FastFeed))
	mm.ReturnCode(rc)
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G%.1f Y%.4f F%.1f", ProbeCode, ProbeToYm, SlowFeed))
	mm.ReturnCode(rc)
	rc = Probing.CheckProbe(0, ProbeCode); if not rc then; do return end; end
	local MeasPointY2ABS = mc.mcCntlGetPoundVar(inst, mc.SV_PROBE_POS_Y)
	local MeasPointY2MACH = mc.mcCntlGetPoundVar(inst,mc.SV_PROBE_MACH_POS_Y)
	
	------------- Calculate Y Center -------------
	MeasPointY1ABS = MeasPointY1ABS + ProbeRad + YOffset
	MeasPointY1MACH = MeasPointY1MACH + ProbeRad + YOffset
	MeasPointY2ABS = MeasPointY2ABS - ProbeRad + YOffset
	MeasPointY2MACH = MeasPointY2MACH - ProbeRad + YOffset
	local CenterPointYABS = (MeasPointY1ABS + MeasPointY2ABS) / 2
	local CenterPointYMACH = (MeasPointY1MACH + MeasPointY2MACH) / 2
	
	mc.mcCntlGcodeExecuteWait(inst, string.format("G1 Y%.4f F%.1f", CenterPointYABS, FastFeed))
	
	------------- Calculate and set offset/vars -------------
	local PosErrorX = CenterPointXABS - CurXPosition
	local PosErrorY = CenterPointYABS - CurYPosition
	local MeasDiam = ((MeasPointX1ABS - MeasPointX2ABS) + (MeasPointY1ABS - MeasPointY2ABS)) / 2
	local DiamError = MeasDiam - Diam
	
	mc.mcCntlSetPoundVar(inst, 131, CenterPointXMACH)
	mc.mcCntlSetPoundVar(inst, 132, CenterPointYMACH)
	mc.mcCntlSetPoundVar(inst, 141, CenterPointXABS)
	mc.mcCntlSetPoundVar(inst, 142, CenterPointYABS)
	mc.mcCntlSetPoundVar(inst, 144, MeasDiam)
	mc.mcCntlSetPoundVar(inst, 135, PosErrorX)
	mc.mcCntlSetPoundVar(inst, 136, PosErrorY)
	mc.mcCntlSetPoundVar(inst, 138, DiamError)
	
	if (SetWork == 1) then
		Probing.SetFixOffset(CenterPointXMACH, CenterPointYMACH, nil)
	end
	
	------------- Reset State ------------------------------------
	mc.mcCntlSetPoundVar(inst, mc.SV_FEEDRATE, CurFeed)
	mc.mcCntlSetPoundVar(inst, mc.SV_MOD_GROUP_1, CurFeedMode)
	mc.mcCntlSetPoundVar(inst, mc.SV_MOD_GROUP_3, CurAbsMode)
end

function Probing.Boss(diam, approach, zpos, work)
	local inst = mc.mcGetInstance()
	------------- Errors -------------
	if (diam == nil) then
		mc.mcCntlSetLastError(inst, "Probe: Boss diam not input")
		do return end
	end
	if (approach == nil) then
		mc.mcCntlSetLastError(inst, "Probe: Approach not input")
		do return end
	end
	if (zpos == nil) then
		mc.mcCntlSetLastError(inst, "Probe: Z measure position not input")
		do return end
	end
	
	------------- Define Vars -------------
	Probing.NilVars(100, 150)
	local Diam = tonumber(diam)
	local Approach = tonumber(approach)
	local ZLevel = tonumber(zpos)
	
	local SetWork = tonumber(work)
	
	local ProbeRad = mc.mcProfileGetDouble(inst, "ProbingSettings", "Radius", 0.000)
	local XOffset = mc.mcProfileGetDouble(inst, "ProbingSettings", "XOffset", 0.000)
	local YOffset = mc.mcProfileGetDouble(inst, "ProbingSettings", "YOffset", 0.000)
	local OffsetNum = mc.mcProfileGetDouble(inst , "ProbingSettings", "OffsetNum", 0.000)
	local SlowFeed = mc.mcProfileGetDouble(inst , "ProbingSettings", "SlowFeed", 0.000)
	local FastFeed = mc.mcProfileGetDouble(inst , "ProbingSettings", "FastFeed", 0.000)
	local BackOff = mc.mcProfileGetDouble(inst , "ProbingSettings", "BackOff", 0.000)
	local OverShoot = mc.mcProfileGetDouble(inst , "ProbingSettings", "OverShoot", 0.000)
	local InPosZone = mc.mcProfileGetDouble(inst , "ProbingSettings", "InPosZone", 0.000)
	local ProbeCode = mc.mcProfileGetDouble(inst , "ProbingSettings", "GCode", 0.000)
	
	------------- Get current state -------------
	local CurFeed = mc.mcCntlGetPoundVar(inst, mc.SV_FEEDRATE)
	local CurZOffset = mc.mcCntlGetPoundVar(inst, mc.SV_ORIGIN_OFFSET_Z)
	local CurFeedMode = mc.mcCntlGetPoundVar(inst, mc.SV_MOD_GROUP_1)
	local CurAbsMode = mc.mcCntlGetPoundVar(inst, mc.SV_MOD_GROUP_3)
	local CurXPosition = mc.mcAxisGetPos(inst, mc.X_AXIS)
	local CurYPosition = mc.mcAxisGetPos(inst, mc.Y_AXIS)
	local CurZPosition = mc.mcAxisGetPos(inst, mc.Z_AXIS)
	
	------------- Check Probe -------------
	rc = Probing.CheckProbe(1, ProbeCode); if not rc then; do return end; end
	
	------------- Probing positions -------------
	local ProbeToXp = CurXPosition + (Diam / 2) - OverShoot
	local ProbeToXm = CurXPosition - (Diam / 2) + OverShoot
	local ProbeToYp = CurYPosition + (Diam / 2) - OverShoot
	local ProbeToYm = CurYPosition - (Diam / 2) + OverShoot
	
	------------- Probing sequence -------------
	local rc = mc.mcCntlGcodeExecuteWait(inst, "G0 G90 G40 G80")
	mm.ReturnCode(rc)
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G43 H%.0f", OffsetNum))
	mm.ReturnCode(rc)
	local ProbeTo = ProbeToYp
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G%.1f Y%.4f F%.1f", ProbeCode, ProbeTo + Approach, FastFeed))
	mm.ReturnCode(rc)
	rc = Probing.CheckProbe(1, ProbeCode); if not rc then; do return end; end
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G%.1f Z%.4f F%.1f", ProbeCode, ZLevel, FastFeed))
	mm.ReturnCode(rc)
	rc = Probing.CheckProbe(1, ProbeCode); if not rc then; do return end; end
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G%.1f Y%.4f F%.1f", ProbeCode, ProbeTo, FastFeed))
	mm.ReturnCode(rc)
	rc = Probing.CheckProbe(0, ProbeCode); if not rc then; do return end; end
	local MeasPointY1ABS = mc.mcCntlGetPoundVar(inst, mc.SV_PROBE_POS_Y)
	if ((ProbeTo + Approach) < ProbeTo) then
		MeasPointY1ABS = MeasPointY1ABS + ProbeRad + YOffset
	else
		MeasPointY1ABS = MeasPointY1ABS - ProbeRad + YOffset
	end
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G1 Y%.4f F%.1f", ProbeTo + Approach, FastFeed))
	mm.ReturnCode(rc)
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G1 Z%.4f F%.1f", CurZPosition, FastFeed))
	mm.ReturnCode(rc)
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G%.1f Y%.4f F%.1f", ProbeCode, CurYPosition, FastFeed))
	mm.ReturnCode(rc)
	rc = Probing.CheckProbe(1, ProbeCode); if not rc then; do return end; end
	local ProbeTo = ProbeToYm
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G%.1f Y%.4f F%.1f", ProbeCode, ProbeTo - Approach, FastFeed))
	mm.ReturnCode(rc)
	rc = Probing.CheckProbe(1, ProbeCode); if not rc then; do return end; end
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G%.1f Z%.4f F%.1f", ProbeCode, ZLevel, FastFeed))
	mm.ReturnCode(rc)
	rc = Probing.CheckProbe(1, ProbeCode); if not rc then; do return end; end
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G%.1f Y%.4f F%.1f", ProbeCode, ProbeTo, FastFeed))
	mm.ReturnCode(rc)
	rc = Probing.CheckProbe(0, ProbeCode); if not rc then; do return end; end
	local MeasPointY2ABS = mc.mcCntlGetPoundVar(inst, mc.SV_PROBE_POS_Y)
	if ((ProbeTo - Approach) < ProbeTo) then
		MeasPointY2ABS = MeasPointY2ABS + ProbeRad + YOffset
	else
		MeasPointY2ABS = MeasPointY2ABS - ProbeRad + YOffset
	end
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G1 Y%.4f F%.1f", ProbeTo - Approach, FastFeed))
	mm.ReturnCode(rc)
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G1 Z%.4f F%.1f", CurZPosition, FastFeed))
	mm.ReturnCode(rc)
	
	local YCenter = (MeasPointY1ABS + MeasPointY2ABS) / 2
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G%.1f Y%.4f F%.1f", ProbeCode, YCenter, FastFeed))
	mm.ReturnCode(rc)
	rc = Probing.CheckProbe(1, ProbeCode); if not rc then; do return end; end
	
	------------- Find X Center -------------
	--Measure X plus
	ProbeTo = ProbeToXp
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G%.1f X%.4f F%.1f", ProbeCode, ProbeTo + Approach, FastFeed))
	mm.ReturnCode(rc)
	rc = Probing.CheckProbe(1, ProbeCode); if not rc then; do return end; end
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G%.1f Z%.4f F%.1f", ProbeCode, ZLevel, FastFeed))
	mm.ReturnCode(rc)
	rc = Probing.CheckProbe(1, ProbeCode); if not rc then; do return end; end
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G%.1f X%.4f F%.1f", ProbeCode, ProbeTo, FastFeed))
	mm.ReturnCode(rc)
	rc = Probing.CheckProbe(0, ProbeCode); if not rc then; do return end; end
	local ProbePoint = mc.mcCntlGetPoundVar(inst, mc.SV_PROBE_POS_X)
	if ((ProbeTo + Approach) < ProbeTo) then
		RetractPoint = ProbePoint - BackOff
	else
		RetractPoint = ProbePoint + BackOff
	end
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G1 X%.4f F%.1f", RetractPoint, FastFeed))
	mm.ReturnCode(rc)
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G%.1f X%.4f F%.1f", ProbeCode, ProbeTo, SlowFeed))
	mm.ReturnCode(rc)
	rc = Probing.CheckProbe(0, ProbeCode); if not rc then; do return end; end
	local MeasPointX1ABS = mc.mcCntlGetPoundVar(inst, mc.SV_PROBE_POS_X)
	local MeasPointX1MACH = mc.mcCntlGetPoundVar(inst,mc.SV_PROBE_MACH_POS_X)
	if ((ProbeTo + Approach) < ProbeTo) then
		MeasPointX1ABS = MeasPointX1ABS + ProbeRad + XOffset
		MeasPointX1MACH = MeasPointX1MACH + ProbeRad + XOffset
	else
		MeasPointX1ABS = MeasPointX1ABS - ProbeRad + XOffset
		MeasPointX1MACH = MeasPointX1MACH - ProbeRad + XOffset
	end
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G1 X%.4f F%.1f", ProbeTo + Approach, FastFeed))
	mm.ReturnCode(rc)
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G1 Z%.4f F%.1f", CurZPosition, FastFeed))
	mm.ReturnCode(rc)
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G%.1f X%.4f F%.1f", ProbeCode, CurXPosition, FastFeed))
	mm.ReturnCode(rc)
	rc = Probing.CheckProbe(1, ProbeCode); if not rc then; do return end; end
	--Measure X minus
	ProbeTo = ProbeToXm
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G%.1f X%.4f F%.1f", ProbeCode, ProbeTo - Approach, FastFeed))
	mm.ReturnCode(rc)
	rc = Probing.CheckProbe(1, ProbeCode); if not rc then; do return end; end
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G%.1f Z%.4f F%.1f", ProbeCode, ZLevel, FastFeed))
	mm.ReturnCode(rc)
	rc = Probing.CheckProbe(1, ProbeCode); if not rc then; do return end; end
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G%.1f X%.4f F%.1f", ProbeCode, ProbeTo, FastFeed))
	mm.ReturnCode(rc)
	rc = Probing.CheckProbe(0, ProbeCode); if not rc then; do return end; end
	ProbePoint = mc.mcCntlGetPoundVar(inst, mc.SV_PROBE_POS_X)
	if ((ProbeTo - Approach) < ProbeTo) then
		RetractPoint = ProbePoint - BackOff
	else
		RetractPoint = ProbePoint + BackOff
	end
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G1 X%.4f F%.1f", RetractPoint, FastFeed))
	mm.ReturnCode(rc)
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G%.1f X%.4f F%.1f", ProbeCode, ProbeTo, SlowFeed))
	mm.ReturnCode(rc)
	rc = Probing.CheckProbe(0, ProbeCode); if not rc then; do return end; end
	local MeasPointX2ABS = mc.mcCntlGetPoundVar(inst, mc.SV_PROBE_POS_X)
	local MeasPointX2MACH = mc.mcCntlGetPoundVar(inst,mc.SV_PROBE_MACH_POS_X)
	if ((ProbeTo - Approach) < ProbeTo) then
		MeasPointX2ABS = MeasPointX2ABS + ProbeRad + XOffset
		MeasPointX2MACH = MeasPointX2MACH + ProbeRad + XOffset
	else
		MeasPointX2ABS = MeasPointX2ABS - ProbeRad + XOffset
		MeasPointX2MACH = MeasPointX2MACH - ProbeRad + XOffset
	end
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G1 X%.4f F%.1f", ProbeTo - Approach, FastFeed))
	mm.ReturnCode(rc)
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G1 Z%.4f F%.1f", CurZPosition, FastFeed))
	mm.ReturnCode(rc)
	
	------------- Calculate X Center -------------
	local CenterPointXABS = (MeasPointX1ABS + MeasPointX2ABS) / 2
	local CenterPointXMACH = (MeasPointX1MACH + MeasPointX2MACH) / 2
	
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G%.1f X%.4f F%.1f", ProbeCode, CenterPointXABS, FastFeed))
	mm.ReturnCode(rc)
	rc = Probing.CheckProbe(1, ProbeCode); if not rc then; do return end; end
	
	------------- Find Y Center -------------
	--Measure Y plus
	ProbeTo = ProbeToYp
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G%.1f Y%.4f F%.1f", ProbeCode, ProbeTo + Approach, FastFeed))
	mm.ReturnCode(rc)
	rc = Probing.CheckProbe(1, ProbeCode); if not rc then; do return end; end
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G%.1f Z%.4f F%.1f", ProbeCode, ZLevel, FastFeed))
	mm.ReturnCode(rc)
	rc = Probing.CheckProbe(1, ProbeCode); if not rc then; do return end; end
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G%.1f Y%.4f F%.1f", ProbeCode, ProbeTo, FastFeed))
	mm.ReturnCode(rc)
	rc = Probing.CheckProbe(0, ProbeCode); if not rc then; do return end; end
	ProbePoint = mc.mcCntlGetPoundVar(inst, mc.SV_PROBE_POS_Y)
	if ((ProbeTo + Approach) < ProbeTo) then
		RetractPoint = ProbePoint - BackOff
	else
		RetractPoint = ProbePoint + BackOff
	end
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G1 Y%.4f F%.1f", RetractPoint, FastFeed))
	mm.ReturnCode(rc)
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G%.1f Y%.4f F%.1f", ProbeCode, ProbeTo, SlowFeed))
	mm.ReturnCode(rc)
	rc = Probing.CheckProbe(0, ProbeCode); if not rc then; do return end; end
	MeasPointY1ABS = mc.mcCntlGetPoundVar(inst, mc.SV_PROBE_POS_Y)
	local MeasPointY1MACH = mc.mcCntlGetPoundVar(inst,mc.SV_PROBE_MACH_POS_Y)
	if ((ProbeTo + Approach) < ProbeTo) then
		MeasPointY1ABS = MeasPointY1ABS + ProbeRad + YOffset
		MeasPointY1MACH = MeasPointY1MACH + ProbeRad + YOffset
	else
		MeasPointY1ABS = MeasPointY1ABS - ProbeRad + YOffset
		MeasPointY1MACH = MeasPointY1MACH - ProbeRad + YOffset
	end
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G1 Y%.4f F%.1f", ProbeTo + Approach, FastFeed))
	mm.ReturnCode(rc)
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G1 Z%.4f F%.1f", CurZPosition, FastFeed))
	mm.ReturnCode(rc)
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G%.1f Y%.4f F%.1f", ProbeCode, CurYPosition, FastFeed))
	mm.ReturnCode(rc)
	rc = Probing.CheckProbe(1, ProbeCode); if not rc then; do return end; end
	--Measure Y minus
	ProbeTo = ProbeToYm
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G%.1f Y%.4f F%.1f", ProbeCode, ProbeTo - Approach, FastFeed))
	mm.ReturnCode(rc)
	rc = Probing.CheckProbe(1, ProbeCode); if not rc then; do return end; end
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G%.1f Z%.4f F%.1f", ProbeCode, ZLevel, FastFeed))
	mm.ReturnCode(rc)
	rc = Probing.CheckProbe(1, ProbeCode); if not rc then; do return end; end
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G%.1f Y%.4f F%.1f", ProbeCode, ProbeTo, FastFeed))
	mm.ReturnCode(rc)
	rc = Probing.CheckProbe(0, ProbeCode); if not rc then; do return end; end
	local ProbePoint = mc.mcCntlGetPoundVar(inst, mc.SV_PROBE_POS_Y)
	if ((ProbeTo - Approach) < ProbeTo) then
		RetractPoint = ProbePoint - BackOff
	else
		RetractPoint = ProbePoint + BackOff
	end
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G1 Y%.4f F%.1f", RetractPoint, FastFeed))
	mm.ReturnCode(rc)
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G%.1f Y%.4f F%.1f", ProbeCode, ProbeTo, SlowFeed))
	mm.ReturnCode(rc)
	rc = Probing.CheckProbe(0, ProbeCode); if not rc then; do return end; end
	MeasPointY2ABS = mc.mcCntlGetPoundVar(inst, mc.SV_PROBE_POS_Y)
	local MeasPointY2MACH = mc.mcCntlGetPoundVar(inst,mc.SV_PROBE_MACH_POS_Y)
	if ((ProbeTo - Approach) < ProbeTo) then
		MeasPointY2ABS = MeasPointY2ABS + ProbeRad + YOffset
		MeasPointY2MACH = MeasPointY2MACH + ProbeRad + YOffset
	else
		MeasPointY2ABS = MeasPointY2ABS - ProbeRad + YOffset
		MeasPointY2MACH = MeasPointY2MACH - ProbeRad + YOffset
	end
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G1 Y%.4f F%.1f", ProbeTo - Approach, FastFeed))
	mm.ReturnCode(rc)
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G1 Z%.4f F%.1f", CurZPosition, FastFeed))
	mm.ReturnCode(rc)
	
	------------- Calculate Y Center -------------
	local CenterPointYABS = (MeasPointY1ABS + MeasPointY2ABS) / 2
	local CenterPointYMACH = (MeasPointY1MACH + MeasPointY2MACH) / 2
	
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G%.1f Y%.4f F%.1f", ProbeCode, CenterPointYABS, FastFeed))
	mm.ReturnCode(rc)
	rc = Probing.CheckProbe(1, ProbeCode); if not rc then; do return end; end
	
	------------- Calculate and set offset/vars -------------
	local PosErrorX = CenterPointXABS - CurXPosition
	local PosErrorY = CenterPointYABS - CurYPosition
	local MeasDiam = ((MeasPointX1ABS - MeasPointX2ABS) + (MeasPointY1ABS - MeasPointY2ABS)) / 2
	local DiamError = MeasDiam - Diam
	
	mc.mcCntlSetPoundVar(inst, 131, CenterPointXMACH)
	mc.mcCntlSetPoundVar(inst, 132, CenterPointYMACH)
	mc.mcCntlSetPoundVar(inst, 141, CenterPointXABS)
	mc.mcCntlSetPoundVar(inst, 142, CenterPointYABS)
	mc.mcCntlSetPoundVar(inst, 144, MeasDiam)
	mc.mcCntlSetPoundVar(inst, 135, PosErrorX)
	mc.mcCntlSetPoundVar(inst, 136, PosErrorY)
	mc.mcCntlSetPoundVar(inst, 138, DiamError)
	
	if (SetWork == 1) then
		Probing.SetFixOffset(CenterPointXMACH, CenterPointYMACH, nil)
	end
	
	------------- Reset State ------------------------------------
	mc.mcCntlSetPoundVar(inst, mc.SV_FEEDRATE, CurFeed)
	mc.mcCntlSetPoundVar(inst, mc.SV_MOD_GROUP_1, CurFeedMode)
	mc.mcCntlSetPoundVar(inst, mc.SV_MOD_GROUP_3, CurAbsMode)
end



function Probing.SingleAngleY(ypos, xinc, xcntr, ycntr, rotate)
	local inst = mc.mcGetInstance()
	------------- Errors -------------
	if (ypos == nil) then
		mc.mcCntlSetLastError(inst, "Probe: Y position not input")
		do return end
	end
	if (xinc == nil) then
		mc.mcCntlSetLastError(inst, "Probe: X increment not input")
		do return end
	end
	
	------------- Define Vars -------------
	Probing.NilVars(100, 150)
	local YPos = tonumber(ypos)
	local XInc = tonumber(xinc)
	
	if (xcntr == nil) then
		local XCntr = 0
	else
		local XCntr = tonumber(xcntr)
	end
	if (ycntr == nil) then
		local YCntr = 0
	else
		local YCntr = tonumber(ycntr)
	end
	
	local RotateCoord = tonumber(rotate)
	
	local ProbeRad = mc.mcProfileGetDouble(inst, "ProbingSettings", "Radius", 0.000)
	local XOffset = mc.mcProfileGetDouble(inst, "ProbingSettings", "XOffset", 0.000)
	local YOffset = mc.mcProfileGetDouble(inst, "ProbingSettings", "YOffset", 0.000)
	local OffsetNum = mc.mcProfileGetDouble(inst , "ProbingSettings", "OffsetNum", 0.000)
	local SlowFeed = mc.mcProfileGetDouble(inst , "ProbingSettings", "SlowFeed", 0.000)
	local FastFeed = mc.mcProfileGetDouble(inst , "ProbingSettings", "FastFeed", 0.000)
	local BackOff = mc.mcProfileGetDouble(inst , "ProbingSettings", "BackOff", 0.000)
	local OverShoot = mc.mcProfileGetDouble(inst , "ProbingSettings", "OverShoot", 0.000)
	local InPosZone = mc.mcProfileGetDouble(inst , "ProbingSettings", "InPosZone", 0.000)
	local ProbeCode = mc.mcProfileGetDouble(inst , "ProbingSettings", "GCode", 0.000)
	
	------------- Get current state -------------
	local CurFeed = mc.mcCntlGetPoundVar(inst, mc.SV_FEEDRATE)
	local CurZOffset = mc.mcCntlGetPoundVar(inst, mc.SV_ORIGIN_OFFSET_Z)
	local CurFeedMode = mc.mcCntlGetPoundVar(inst, mc.SV_MOD_GROUP_1)
	local CurAbsMode = mc.mcCntlGetPoundVar(inst, mc.SV_MOD_GROUP_3)
	local CurPlane = mc.mcCntlGetPoundVar(inst, mc.SV_MOD_GROUP_2)
	local CurXPosition = mc.mcAxisGetPos(inst, mc.X_AXIS)
	local CurYPosition = mc.mcAxisGetPos(inst, mc.Y_AXIS)
	
	if (CurPlane ~= 170) and (RotateCoord == 1) then
		mc.mcCntlSetLastError(inst, "Probe: Invalid plane selection for coordinate rotation")
		do return end
	end
	
	------------- Check Probe -------------
	rc = Probing.CheckProbe(1, ProbeCode); if not rc then; do return end; end
	
	------------- Check direction -------------
	if (CurYPosition > YPos) then
		BackOff = -BackOff
		OverShoot = -OverShoot
		ProbeRad = -ProbeRad
	end
	
	------------- Probe X Surface -------------
	local ProbeTo = YPos + OverShoot
	local rc = mc.mcCntlGcodeExecuteWait(inst, "G0 G90 G40 G80")
	mm.ReturnCode(rc)
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G%.1f Y%.4f F%.1f", ProbeCode, ProbeTo, FastFeed))
	mm.ReturnCode(rc)
	rc = Probing.CheckProbe(0, ProbeCode); if not rc then; do return end; end
	local ProbePoint = mc.mcCntlGetPoundVar(inst, mc.SV_PROBE_POS_Y)
	local RetractPoint = ProbePoint - BackOff
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G1 Y%.4f F%.1f", RetractPoint, FastFeed))
	mm.ReturnCode(rc)
	--Measure
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G%.1f Y%.4f F%.1f", ProbeCode, ProbeTo, SlowFeed))
	mm.ReturnCode(rc)
	rc = Probing.CheckProbe(0, ProbeCode); if not rc then; do return end; end
	local MeasPoint1ABS = mc.mcCntlGetPoundVar(inst, mc.SV_PROBE_POS_Y) + ProbeRad + YOffset
	local MeasPoint1MACH = mc.mcCntlGetPoundVar(inst,mc.SV_PROBE_MACH_POS_Y) + ProbeRad + YOffset
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G1Y%.4f F%.1f", CurYPosition, FastFeed))
	mm.ReturnCode(rc)
	
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G%.1f X%.4f F%.1f", ProbeCode, CurXPosition + XInc, FastFeed))
	mm.ReturnCode(rc)
	rc = Probing.CheckProbe(1, ProbeCode); if not rc then; do return end; end
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G%.1f Y%.4f F%.1f", ProbeCode, ProbeTo, FastFeed))
	mm.ReturnCode(rc)
	rc = Probing.CheckProbe(0, ProbeCode); if not rc then; do return end; end
	local ProbePoint = mc.mcCntlGetPoundVar(inst, mc.SV_PROBE_POS_Y)
	local RetractPoint = ProbePoint - BackOff
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G1 Y%.4f F%.1f", RetractPoint, FastFeed))
	mm.ReturnCode(rc)
	--Measure
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G%.1f Y%.4f F%.1f", ProbeCode, ProbeTo, SlowFeed))
	mm.ReturnCode(rc)
	rc = Probing.CheckProbe(0, ProbeCode); if not rc then; do return end; end
	local MeasPoint2ABS = mc.mcCntlGetPoundVar(inst, mc.SV_PROBE_POS_Y) + ProbeRad + YOffset
	local MeasPoint2MACH = mc.mcCntlGetPoundVar(inst,mc.SV_PROBE_MACH_POS_Y) + ProbeRad + YOffset
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G1 Y%.4f F%.1f",  CurYPosition, FastFeed))
	mm.ReturnCode(rc)
	
	rc = mc.mcCntlGcodeExecuteWait(inst, string.format("G1 X%.4f F%.1f",  CurXPosition, FastFeed))
	mm.ReturnCode(rc)
	
	
	------------- Calculate and set offset/vars -------------
	
	--Calculate angles and intercept from multi point measurement
	local MachShift = MeasPoint1MACH - MeasPoint1ABS
	local V1X = CurXPosition
    local V1i = XInc
    local V1Y = MeasPoint1ABS
    local V1j = MeasPoint2ABS - MeasPoint1ABS
	
	local Angle = Probing.VectorAngle2D(V1i, V1j, V1i, 0)
	if (V1i < 0) and (V1j > 0) and (Angle > 0) then
		Angle = -Angle
	elseif (V1i > 0) and (V1j < 0) and (Angle > 0) then
		Angle = -Angle
	end

	mc.mcCntlSetPoundVar(inst, 144, Angle)
	mc.mcCntlSetPoundVar(inst, 138, Angle)
	
	if (RotateCoord == 1) then
		mc.mcCntlGcodeExecuteWait(inst, string.format("G68 X%.4f Y%.4f R%.4f", XCntr, YCntr, Angle))
	end
	
	------------- Reset State ------------------------------------
	mc.mcCntlSetPoundVar(inst, mc.SV_FEEDRATE, CurFeed)
	mc.mcCntlSetPoundVar(inst, mc.SV_MOD_GROUP_1, CurFeedMode)
	mc.mcCntlSetPoundVar(inst, mc.SV_MOD_GROUP_3, CurAbsMode)
end


function Probing.LoadSettings()
	local inst = mc.mcGetInstance()
	local ProbeRad = mc.mcProfileGetString(inst, "ProbingSettings", "Radius", "0")
	scr.SetProperty("droCalProbeRad", "Value", ProbeRad)
	local XOffset = mc.mcProfileGetString(inst, "ProbingSettings", "XOffset", "0")
	scr.SetProperty("droCalXOffset", "Value", XOffset)
	local YOffset = mc.mcProfileGetString(inst, "ProbingSettings", "YOffset", "0")
	scr.SetProperty("droCalYOffset", "Value", YOffset)
	local OffsetNum = mc.mcProfileGetString(inst , "ProbingSettings", "OffsetNum", "0")
	scr.SetProperty("droPrbOffNum", "Value", OffsetNum)
	local SlowFeed = mc.mcProfileGetString(inst , "ProbingSettings", "SlowFeed", "0")
	scr.SetProperty("droSlowFeed", "Value", SlowFeed)
	local FastFeed = mc.mcProfileGetString(inst , "ProbingSettings", "FastFeed", "0")
	scr.SetProperty("droFastFeed", "Value", FastFeed)
	local BackOff = mc.mcProfileGetString(inst , "ProbingSettings", "BackOff", "0")
	scr.SetProperty("droBackOff", "Value", BackOff)
	local OverShoot = mc.mcProfileGetString(inst , "ProbingSettings", "OverShoot", "0")
	scr.SetProperty("droOverShoot", "Value", OverShoot)
	local InPosZone = mc.mcProfileGetString(inst , "ProbingSettings", "InPosZone", "0")
	scr.SetProperty("droPrbInPos", "Value", InPosZone)
	local ProbeCode = mc.mcProfileGetString(inst , "ProbingSettings", "GCode", "0")
	scr.SetProperty("droPrbGcode", "Value", ProbeCode)
end

return Probing

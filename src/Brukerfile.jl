
include("Jcampdx.jl")


export BrukerFile

function latin1toutf8(str::AbstractString)
  buff = Char[]
  for c in str.data
    push!(buff,c)
  end
  string(buff...)
end

type BrukerFile <: MPIFile
  path::String
  params::JcampdxFile
  paramsProc::JcampdxFile
  methodRead
  acqpRead
  visupars_globalRead
  recoRead
  methrecoRead
  visuparsRead
  maxEntriesAcqp

  function BrukerFile(path::String, maxEntriesAcqp=2000)
    params = JcampdxFile()
    paramsProc = JcampdxFile()
    return new(path, params, paramsProc, false, false, false,
               false, false, false, maxEntriesAcqp)
  end

end

BrukerFileFast(path) = BrukerFile(path, 400)

function getindex(b::BrukerFile, parameter)
  if !b.acqpRead && ( parameter=="NA" || parameter[1:3] == "ACQ" )
    acqppath = joinpath(b.path, "acqp")
    read(b.params, acqppath, maxEntries=b.maxEntriesAcqp)
    b.acqpRead = true
  elseif !b.methodRead && length(parameter) >= 3 &&
         (parameter[1:3] == "PVM" || parameter[1:3] == "MPI")
    methodpath = joinpath(b.path, "method")
    read(b.params, methodpath)
    b.methodRead = true
  elseif !b.visupars_globalRead && length(parameter) >= 4 &&
         parameter[1:4] == "Visu"
    visupath = joinpath(b.path, "visu_pars")
    read(b.params, visupath, maxEntries=55)
    b.visupars_globalRead = true
  end

  if haskey(b.params, parameter)
    return b.params[parameter]
  else
    return nothing
  end
end

function getindex(b::BrukerFile, parameter, procno::Int64)
  if !b.recoRead && lowercase( parameter[1:4] ) == "reco"
    recopath = joinpath(b.path, "pdata", string(procno), "reco")
    read(b.paramsProc, acqppath, maxEntries=13)
    b.recoRead = true
  elseif !b.methrecoRead && parameter[1:3] == "PVM"
    methrecopath = joinpath(b.path, "pdata", string(procno), "methreco")
    read(b.paramsProc, methrecopath)
    b.methrecoRead = true
  elseif !b.visuparsRead && parameter[1:4] == "Visu"
    visuparspath = joinpath(b.path, "pdata", string(procno), "visu_pars")
    read(b.paramsProc, visuparspath)
    b.visuparsRead = true
  end

  return b.paramsProc[parameter]
end

function Base.show(io::IO, b::BrukerFile)
  print(io, "BrukerFile: ", b.path)
end

# Helper
activeChannels(b::BrukerFile) = [parse(Int64,s) for s=b["PVM_MPI_ActiveChannels"]]
selectedChannels(b::BrukerFile) = b["PVM_MPI_ChannelSelect"] .== "Yes"
selectedReceivers(b::BrukerFile) = b["ACQ_ReceiverSelect"] .== "Yes"

# general parameters
version(b::BrukerFile) = nothing
uuid(b::BrukerFile) = nothing
time(b::BrukerFile) = nothing

# study parameters
studyName(b::BrukerFile) = string(experimentSubject(b),"_",
                                  latin1toutf8(b["VisuStudyId"]),"_",
                                  b["VisuStudyNumber"])
studyNumber(b::BrukerFile) = parse(Int64,b["VisuStudyNumber"])
studyDescription(b::BrukerFile) = "n.a."

# study parameters
experimentName(b::BrukerFile) = latin1toutf8(b["ACQ_scan_name"])
experimentNumber(b::BrukerFile) = parse(Int64,b["VisuExperimentNumber"])
experimentDescription(b::BrukerFile) = latin1toutf8(b["ACQ_scan_name"])
experimentSubject(b::BrukerFile) = latin1toutf8(b["VisuSubjectName"])
experimentIsSimulation(b::BrukerFile) = false
experimentIsCalibration(b::BrukerFile) = b["PVM_Matrix"] != nothing
experimentHasProcessing(b::BrukerFile) = experimentIsCalibration(b)

# tracer parameters
tracerName(b::BrukerFile) = [b["PVM_MPI_Tracer"]]
tracerBatch(b::BrukerFile) = [b["PVM_MPI_TracerBatch"]]
tracerVolume(b::BrukerFile) = [parse(Float64,b["PVM_MPI_TracerVolume"])*1e-6]
tracerConcentration(b::BrukerFile) = [parse(Float64,b["PVM_MPI_TracerConcentration"])]
tracerSolute(b::BrukerFile) = ["Fe"]
function tracerInjectionTime(b::BrukerFile)
  initialFrames = b["MPI_InitialFrames"]
  if initialFrames == nothing
    return [acqStartTime(b)]
  else
    return [acqStartTime(b) + Dates.Millisecond(
       round(Int64,parse(Int64, initialFrames)*dfPeriod(b)*1000 ) )]
  end
end
tracerVendor(b::BrukerFile) = ["n.a."]

# scanner parameters
scannerFacility(b::BrukerFile) = latin1toutf8(b["ACQ_institution"])
scannerOperator(b::BrukerFile) = latin1toutf8(b["ACQ_operator"])
scannerManufacturer(b::BrukerFile) = "Bruker/Philips"
scannerModel(b::BrukerFile) = b["ACQ_station"]
scannerTopology(b::BrukerFile) = "FFP"

# acquisition parameters
function acqStartTime(b::BrukerFile)
  acq = b["ACQ_time"] #b["VisuAcqDate"]
  DateTime( replace(acq[2:search(acq,'+')-1],",",".") )
end
acqNumFrames(b::BrukerFile) = Int64(b["ACQ_jobs"][1][8])
function acqNumBGFrames(b::BrukerFile)
  n = b["PVM_MPI_NrBackgroundMeasurementCalibrationAllScans"]
  if n == nothing
    return 0
  else
    return parse(Int64,n)
  end
end
acqFramePeriod(b::BrukerFile) = dfPeriod(b) * rxNumAverages(b)
acqNumPatches(b::BrukerFile) = 1
acqGradient(b::BrukerFile) = [-0.5 -0.5 1.0].*
      parse(Float64,b["ACQ_MPI_selection_field_gradient"])
function acqOffsetField(b::BrukerFile) #TODO NOT correct
  voltage = [parse(Float64,s) for s in b["ACQ_MPI_frame_list"]]
  calibFac = [2.5/49.45, -2.5*0.008/-22.73, 2.5*0.008/-22.73, 1.5*0.0094/13.2963]
  return addLeadingSingleton( Float64[voltage[d]*calibFac[d] for d=2:4],2)
end
acqOffsetFieldShift(b::BrukerFile) = acqOffsetField(b) ./ acqGradient(b)


# drive-field parameters
dfNumChannels(b::BrukerFile) = sum( selectedReceivers(b)[1:3] .== true )
   #sum( dfStrength(b)[1,:,1] .> 0) #TODO Not sure about this
dfStrength(b::BrukerFile) = addTrailingSingleton( addLeadingSingleton(
  [parse(Float64,s) for s = b["ACQ_MPI_drive_field_strength"] ] *1e-3, 2), 3)
dfPhase(b::BrukerFile) = dfStrength(b) .*0 .+  1.5707963267948966 # Bruker specific!
dfBaseFrequency(b::BrukerFile) = 2.5e6
dfCustomWaveform(b::BrukerFile) = nothing
dfDivider(b::BrukerFile) = addTrailingSingleton([102; 96; 99],2)
dfWaveform(b::BrukerFile) = "sine"
dfPeriod(b::BrukerFile) = parse(Float64,b["PVM_MPI_DriveFieldCycle"]) / 1000
# The following takes faked 1D/2D measurements into account
#function dfPeriod(b::BrukerFile)
#  df = dfStrength(b)
#  return lcm(  dfDivider(b)[ (df .>= 0.0000001) .* selectedChannels(b) ] ) / 2.5e6  # in ms!
#end


# receiver parameters
rxNumChannels(b::BrukerFile) = sum( selectedReceivers(b)[1:3] .== true )
rxNumAverages(b::BrukerFile) = parse(Int,b["NA"])
rxBandwidth(b::BrukerFile) = parse(Float64,b["PVM_MPI_Bandwidth"])*1e6
rxNumSamplingPoints(b::BrukerFile) = parse(Int64,b["ACQ_size"][1])
rxTransferFunction(b::BrukerFile) = nothing

# measurements
measUnit(b::BrukerFile) = "a.u."
measDataConversionFactor(b::BrukerFile) = 1.0
function measData(b::BrukerFile)
  dataFilename = joinpath(b.path,"rawdata")
  dType = rxNumAverages(b) == 1 ? Int16 : Int32

  raw = Rawfile(dataFilename, dType,
             [rxNumSamplingPoints(b),rxNumChannels(b),acqNumFrames(b)],
             extRaw=".job0") #Int or Uint?
  data = raw[]
  return reshape(data,size(data,1),size(data,2),1,size(data,3))
end
measIsBG(f::BrukerFile) = zeros(Bool, acqNumFrames(f))

# processing
# Brukerfiles do only contain processing data in the calibration scans
function procData(b::BrukerFile)
  if !experimentIsCalibration(b)
    return nothing
  end

  bgcorrection = true
  localSFFilename = bgcorrection ? "systemMatrixBG" : "systemMatrix"
  sfFilename = joinpath(b.path,"pdata", "1", localSFFilename)
  nFreq = rxNumFrequencies(b)

  data = Rawfile(sfFilename, Complex128,
                 [prod(calibSize(b)),nFreq,rxNumChannels(b)], extRaw="")
  S = data[]
  return reshape(S,size(S,1),size(S,2),size(S,3),1)
end

function procIsFourierTransformed(b::BrukerFile)
  if !experimentIsCalibration(b)
    return nothing
  else
    return true
  end
end

function procIsTFCorrected(b::BrukerFile)
  if !experimentIsCalibration(b)
    return nothing
  else
    return false
  end
end

function procIsAveraged(b::BrukerFile)
  if !experimentIsCalibration(b)
    return nothing
  else
    return false # I don't think so. Averaging is only applied internally
  end
end

function procIsFramesSelected(b::BrukerFile)
  if !experimentIsCalibration(b)
    return nothing
  else
    return false # Not sure
  end
end

function procIsBGCorrected(b::BrukerFile)
  if !experimentIsCalibration(b)
    return nothing
  else
    return true
  end
end

function procIsTransposed(b::BrukerFile)
  if !experimentIsCalibration(b)
    return nothing
  else
    return true
  end
end

function procFramePermutation(b::BrukerFile)
  if !experimentIsCalibration(b)
    return nothing
  else
    return nothing # TODO
  end
end

# calibrations
function calibSNR(b::BrukerFile)
  snrFilename = joinpath(b.path,"pdata", "1", "snr")
  data = Rawfile(snrFilename, Float64, [rxNumFrequencies(b),rxNumChannels(b)], extRaw="")
  return data[]
end
calibFov(b::BrukerFile) = [parse(Float64,s) for s = b["PVM_Fov"] ] * 1e-3
calibFovCenter(b::BrukerFile) =
          [parse(Float64,s) for s = b["PVM_MPI_FovCenter"] ] * 1e-3
calibSize(b::BrukerFile) = [parse(Int64,s) for s in b["PVM_Matrix"]]
calibOrder(b::BrukerFile) = "xyz"
calibPositions(b::BrukerFile) = nothing
calibOffsetField(b::BrukerFile) = nothing
calibDeltaSampleSize(b::BrukerFile) = nothing #TODO
calibMethod(b::BrukerFile) = "robot"


# additional functions that should be implemented by an MPIFile
filepath(b::BrukerFile) = b.path



# special additional methods

hasSpectralCleaning(b::BrukerFile) = get(b.params, "ACQ_MPI_spectral_cleaningl", "No") != "No"

function sfPath(b::BrukerFile)
  tmp = b["PVM_MPI_FilenameSystemMatrix",1]
  tmp[1:search(tmp,"/pdata")[1]]
end

### The following is for field measurements from Alex Webers method
numCurrentSettings(b::BrukerFile) = parse(Int64,b["MPI_NrCurrentSettings"])
function currentSetting(b::BrukerFile)
  c = Float64[]
  for s in b["MPI_CurrentSetting"]
    append!(c,s)
  end
  return reshape(c,4,div(length(c),4))
end
ballRadius(b::BrukerFile) = parse(Float64,b["MPI_BallRadius"])
numLatitude(b::BrukerFile) = parse(Int64,b["MPI_NrLatitude"])
numMeridian(b::BrukerFile) = parse(Int64,b["MPI_NrMeridian"])

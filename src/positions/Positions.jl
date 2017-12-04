using Unitful, HDF5

import Base: getindex, length, convert, start, done, next, write

export Positions, CartesianGridPositions, ChebyshevGridPositions,
       MeanderingGridPositions, UniformRandomPositions, ArbitraryPositions, SphericalTDesign
export SpatialDomain, AxisAlignedBox, Ball
export loadTDesign, getPermutation
export fieldOfView, fieldOfViewCenter, shape


@compat abstract type Positions end
@compat abstract type GridPositions<:Positions end

function Positions(file::HDF5File)
  typ = read(file, "/positionsType")
  if typ == "CartesianGridPositions"
    positions = CartesianGridPositions(file)
  elseif typ == "ChebyshevGridPositions"
    positions = ChebyshevGridPositions(file)
  elseif typ == "SphericalTDesign"
    positions = SphericalTDesign(file)
  elseif typ == "UniformRandomPositions"
    positions = UniformRandomPositions(file)
  elseif typ == "ArbitraryPositions"
    positions = ArbitraryPositions(file)
  else
    throw(ErrorException("No grid found to load from $file"))
  end

  if exists(file, "/positionsMeandering") && typ in ["CartesianGrid","ChebyshevGrid"] && read(file, "/positionsMeandering") == Int8(1)
    positions = MeanderingGridPositions(positions)
  end

  return positions
end

# Cartesian grid
type CartesianGridPositions{S,T} <: GridPositions where {S,T<:Unitful.Length}
  shape::Vector{Int}
  fov::Vector{S}
  center::Vector{T}
end

function CartesianGridPositions(file::HDF5File)
  shape = read(file, "/positionsShape")
  fov = read(file, "/positionsFov")*u"m"
  center = read(file, "/positionsCenter")*u"m"
  return CartesianGridPositions(shape,fov,center)
end

function write(file::HDF5File, positions::CartesianGridPositions)
  write(file,"/positionsType", "CartesianGridPositions")
  write(file, "/positionsShape", positions.shape)
  write(file, "/positionsFov", Float64.(ustrip.(uconvert.(u"m", positions.fov))) )
  write(file, "/positionsCenter", Float64.(ustrip.(uconvert.(u"m", positions.center))) )
end

function getindex(grid::CartesianGridPositions, i::Integer)
  if i>length(grid) || i<1
    return throw(BoundsError(grid,i))
  else
    idx = collect(ind2sub(tuple(shape(grid)...), i))
    return ((-shape(grid).+(2.*idx.-1))./shape(grid)).*fieldOfView(grid)./2 + fieldOfViewCenter(grid)
  end
end

# Chebyshev Grid
type ChebyshevGridPositions{S,T} <: GridPositions where {S,T<:Unitful.Length}
  shape::Vector{Int}
  fov::Vector{S}
  center::Vector{T}
end

function write(file::HDF5File, positions::ChebyshevGridPositions)
  write(file,"/positionsType", "ChebyshevGridPositions")
  write(file, "/positionsShape", positions.shape)
  write(file, "/positionsFov", Float64.(ustrip.(uconvert.(u"m", positions.fov))) )
  write(file, "/positionsCenter", Float64.(ustrip.(uconvert.(u"m", positions.center))) )
end

function ChebyshevGridPositions(file::HDF5File)
  shape = read(file, "/positionsShape")
  fov = read(file, "/positionsFov")*u"m"
  center = read(file, "/positionsCenter")*u"m"
  return ChebyshevGridPositions(shape,fov,center)
end

function getindex(grid::ChebyshevGridPositions, i::Integer)
  if i>length(grid) || i<1
    throw(BoundsError(grid,i))
  else
    idx = collect(ind2sub(tuple(shape(grid)...), i))
    return -cos.((idx.-0.5).*pi./shape(grid)).*fieldOfView(grid)./2 .+ fieldOfViewCenter(grid)
  end
end

# Meander regular grid positions
type MeanderingGridPositions <: GridPositions
  grid::GridPositions
end

function MeanderingGridPositions(file::HDF5File)
  typ = read(file, "/positionsType")
  if typ == "CartesianGridPositions"
    grid = CartesianGridPositions(file)
    return MeanderingGridPositions(grid)
  elseif typ == "ChebyshevGridPositions"
    grid = ChebyshevGridPositions(file)
    return MeanderingGridPositions(grid)
  end
end

function write(file::HDF5File, positions::MeanderingGridPositions)
  write(file,"/positionsMeandering", Int8(1))
  write(file, positions.grid)
end

function indexPermutation(grid::MeanderingGridPositions, i::Integer)
  dims = tuple(shape(grid)...)
  idx = collect(ind2sub(dims, i))
    for d=2:3
      if isodd(sum(idx[d:3])-length(idx[d:3]))
      idx[d-1] = shape(grid)[d-1] + 1 - idx[d-1]
    end
  end
  linidx = sub2ind(dims,idx...)
end

function getindex(grid::MeanderingGridPositions, i::Integer)
  iperm = indexPermutation(grid,i)
  return grid.grid[iperm]
end

function getPermutation(grid::MeanderingGridPositions)
  N = length(grid)
  perm = Array{Int}(N)

  for i in eachindex(perm)
    perm[i] = indexPermutation(grid,i)
  end
  return vec(perm)
end

#TODO Meander + BG
# capsulate objects of type GridPositions and return to ParkPosition every so often

# Uniform random distributed positions
@compat abstract type SpatialDomain end

struct AxisAlignedBox <: SpatialDomain
  fov::Vector{S} where {S<:Unitful.Length}
  center::Vector{T} where {T<:Unitful.Length}
end

function write(file::HDF5File, domain::AxisAlignedBox)
  write(file, "/positionsDomain", "AxisAlignedBox")
  write(file, "/positionsDomainFieldOfView", Float64.(ustrip.(uconvert.(u"m", domain.fov))) )
  write(file, "/positionsDomainCenter", Float64.(ustrip.(uconvert.(u"m", domain.center))) )
end

function AxisAlignedBox(file::HDF5File)
  fov = read(file, "/positionsDomainFieldOfView")*u"m"
  center = read(file, "/positionsDomainCenter")*u"m"
  return AxisAlignedBox(fov,center)
end

struct Ball <: SpatialDomain
  radius::S where {S<:Unitful.Length}
  center::Vector{T} where {T<:Unitful.Length}
end

function write(file::HDF5File, domain::Ball)
  write(file, "/positionsDomain", "Ball")
  write(file, "/positionsDomainRadius", Float64.(ustrip.(uconvert.(u"m", domain.radius))) )
  write(file, "/positionsDomainCenter", Float64.(ustrip.(uconvert.(u"m", domain.center))) )
end

function Ball(file::HDF5File)
  radius = read(file, "/positionsDomainRadius")*u"m"
  center = read(file, "/positionsDomainCenter")*u"m"
  return Ball(radius,center)
end


type UniformRandomPositions{T} <: Positions where {T<:SpatialDomain}
  N::UInt
  seed::UInt32
  domain::T
end

radius(rpos::UniformRandomPositions{Ball}) = rpos.domain.radius
seed(rpos::UniformRandomPositions) = rpos.seed

function getindex(rpos::UniformRandomPositions{AxisAlignedBox}, i::Integer)
  if i>length(rpos) || i<1
    throw(BoundsError(rpos,i))
  else
    # make sure Positions are randomly generated from given seed
    mersenneTwister = MersenneTwister(seed(rpos))
    rP = rand(mersenneTwister, 3, i)[:,i]
    return (rP.-0.5).*fieldOfView(rpos)+fieldOfViewCenter(rpos)
  end
end

function getindex(rpos::UniformRandomPositions{Ball}, i::Integer)
  if i>length(rpos) || i<1
    throw(BoundsError(rpos,i))
  else
    # make sure Positions are randomly generated from given seed
    mersenneTwister = MersenneTwister(seed(rpos))
    D = rand(mersenneTwister, i)[i]
    P = randn(mersenneTwister, 3, i)[:,i]
    return radius(rpos)*D^(1/3)*normalize(P)+fieldOfViewCenter(rpos)
  end
end

function write(file::HDF5File, positions::UniformRandomPositions{T}) where {T<:SpatialDomain}
  write(file, "/positionsType", "UniformRandomPositions")
  write(file, "/positionsN", positions.N)
  write(file, "/positionsSeed", positions.seed)
  write(file, positions.domain)
end

function UniformRandomPositions(file::HDF5File)
  N = read(file, "/positionsN")
  seed = read(file, "/positionsSeed")
  dom = read(file,"/positionsDomain")
  if dom=="Ball"
    domain = Ball(file)
    return UniformRandomPositions(N,seed,domain)
  elseif dom=="AxisAlignedBox"
    domain = AxisAlignedBox(file)
    return UniformRandomPositions(N,seed,domain)
  else
    throw(ErrorException("No method to read domain $domain"))
  end
end

# TODO fix conversion methods
#=
function convert(::Type{UniformRandomPositions}, N::Integer,seed::UInt32,fov::Vector{S},center::Vector{T}) where {S,T<:Unitful.Length}
  if N<1
    throw(DomainError())
  else
    uN = convert(UInt,N)
    return UniformRandomPositions(uN,seed,fov,center)
  end
end

function convert(::Type{UniformRandomPositions}, N::Integer,fov::Vector,center::Vector)
  return UniformRandomPositions(N,rand(UInt32),fov,center)
end
=#


# General functions for handling grids
fieldOfView(grid::GridPositions) = grid.fov
fieldOfView(grid::UniformRandomPositions{AxisAlignedBox}) = grid.domain.fov
fieldOfView(mgrid::MeanderingGridPositions) = fieldOfView(mgrid.grid)
shape(grid::GridPositions) = grid.shape
shape(mgrid::MeanderingGridPositions) = shape(mgrid.grid)
fieldOfViewCenter(grid::GridPositions) = grid.center
fieldOfViewCenter(grid::UniformRandomPositions) = grid.domain.center
fieldOfViewCenter(mgrid::MeanderingGridPositions) = fieldOfViewCenter(mgrid.grid)


type SphericalTDesign{S,V} <: Positions where {S,V<:Unitful.Length}
  T::Unsigned
  radius::S
  positions::Matrix
  center::Vector{V}
end

function SphericalTDesign(file::HDF5File)
  T = read(file, "/positionsTDesignT")
  N = read(file, "/positionsTDesignN")
  radius = read(file, "/positionsTDesignRadius")*u"m"
  center = read(file, "/positionsCenter")*u"m"
  return loadTDesign(Int64(T),N,radius,center)
end

function write(file::HDF5File, positions::SphericalTDesign)
  write(file,"/positionsType", "SphericalTDesign")
  write(file, "/positionsTDesignT", positions.T)
  write(file, "/positionsTDesignN", size(positions.positions,2))
  write(file, "/positionsTDesignRadius", Float64.(ustrip.(uconvert.(u"m", positions.radius))) )
  write(file, "/positionsCenter", Float64.(ustrip.(uconvert.(u"m", positions.center))) )
end

getindex(tdes::SphericalTDesign, i::Integer) = tdes.radius.*tdes.positions[:,i] + tdes.center

"""
Returns the t-Design Array for choosen t and N.
"""
function loadTDesign(t::Int64, N::Int64, radius::S=10u"mm", center::Vector{V}=[0.0,0.0,0.0]u"mm", filename::String=joinpath(Pkg.dir("MPIFiles"),"src/positions/TDesigns.hd5")) where {S,V<:Unitful.Length}
  h5file = h5open(filename, "r")
  address = "/$t-Design/$N"

  if exists(h5file, address)
    positions = read(h5file, address)'
    return SphericalTDesign(UInt(t),radius,positions, center)
  else
    if exists(h5file, "/$t-Design/")
      println("spherical $t-Design with $N Points does not exist!")
      println("There are spherical $t-Designs with following N:")
      Ns = Int[]
      for N in keys(read(h5file, string("/$t-Design")))
	push!(Ns,parse(Int,N))
      end
      sort!(Ns)
      println(Ns)
      throw(DomainError())
    else
      println("spherical $t-Design does not exist!")
      ts = Int[]
      for d in keys(read(h5file))
	m = match(r"(\d{1,})-(Design)",d)
	if m != nothing
	  push!(ts,parse(Int,m[1]))
        end
      end
      sort!(ts)
      println(ts)
      throw(DomainError())
    end
  end
end

# Unstructured collection of positions
type ArbitraryPositions{T} <: Positions where {T<:Unitful.Length}
  positions::Matrix{T}
end

getindex(apos::ArbitraryPositions, i::Integer) = apos.positions[:,i]

function convert(::Type{ArbitraryPositions}, grid::GridPositions)
  T = eltype(grid.fov)
  positions = zeros(T,3,length(grid))
  for i=1:length(grid)
    positions[:,i] = grid[i]
  end
  return ArbitraryPositions(positions)
end

function write(file::HDF5File, apos::ArbitraryPositions,)
  write(file,"/positionsType", "ArbitraryPositions")
  write(file, "/positionsPositions", Float64.(ustrip.(uconvert.(u"m", apos.positions))) )
end

function ArbitraryPositions(file::HDF5File)
  pos = read(file, "/positionsPositions")*u"m"
  return ArbitraryPositions(pos)
end


# fuction related to looping
length(tdes::SphericalTDesign) = size(tdes.positions,2)
length(apos::ArbitraryPositions) = size(apos.positions,2)
length(grid::GridPositions) = prod(grid.shape)
length(rpos::UniformRandomPositions) = rpos.N
length(mgrid::MeanderingGridPositions) = length(mgrid.grid)
start(grid::Positions) = 1
next(grid::Positions,state) = (grid[state],state+1)
done(grid::Positions,state) = state > length(grid)
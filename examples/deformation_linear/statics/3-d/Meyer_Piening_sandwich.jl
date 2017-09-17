using FinEtools
using FinEtools.AlgoDeforLinearModule
using DataFrames
using CSV

println("""
Meyer-Piening sandwich plate
""")

# Reference results from:
# [1] Application of the Elasticity Solution
# to Linear Sandwich Beam, Plate
# and Shell Analyses
# H.-R. MEYER -PIENING
# Journal of SANDWICH STRUCTURES AND MATERIALS , Vol. 6—July 2004

# Assessment of the refined sinus plate finite element:
# Free edge effect and Meyer-Piening sandwich test
# P. Vidal, O. Polit, M. D'Ottavio, E. Valot
# http://dx.doi.org/10.1016/j.finel.2014.08.004
#
# The second study deals with a benchmark problem proposed
# by Meyer-Piening [14]. It involves a simply -supported rectangular
# sandwich plate submitted to a localized pressure applied on an
# area of 5?20 mm. The geometry of the sandwich structure is
# given in Fig.13. Due to the symmetry, only one quarter of the plate
# is meshed. The faces have different thicknesses: h 1 ¼ 0:5 mm
# (bottom face), h 3 ¼ 0:1 mm (top face). The thickness of the core
# is h 2 ¼ h c ¼ 11:4 mm. The material properties are given in Table 3.
# Note that this benchmark involves strong heterogeneities (very
# different geometric and constitutive properties between core and
# face) and local stress gradient due to the localized pressure load.
#
# [14] H.-R. Meyer-Piening, Experiences with exact linear sandwich beam and plate
# analyses regarding bending, instability and frequency investigations, in:
# Proceedings of the Fifth International Conference On Sandwich Constructions,
# September 5–7, vol. I, Zurich, Switzerland, 2000, pp. 37–48.



t0 = time()
# Orthotropic material for the SKIN
E1s = 70000.0*phun("MPa")
E2s = 71000.0*phun("MPa")
E3s = 69000.0*phun("MPa")
nu12s = nu13s = nu23s = 0.3
G12s = G13s = G23s = 26000.0*phun("MPa")
CTE1 =  CTE2 =  CTE3 = 0.0
# Orthotropic material for the CORE
E1c = 3.0*phun("MPa")
E2c = 3.0*phun("MPa")
E3c = 2.8*phun("MPa")
nu12c = nu13c = nu23c = 0.25
G12c = G13c = G23c = 1.0*phun("MPa")
CTE1 =  CTE2 =  CTE3 = 0.0

Lx = 5.0*phun("mm") # length  of loaded rectangle
Ly = 20.0*phun("mm") # length  of loaded rectangle
Sx = 100.0*phun("mm") # span of the plate
Sy = 200.0*phun("mm") # span of the plate

# Here we define the layout and the thicknesses of the layers.
angles = vec([0.0 0.0 0.0]);
ts = vec([0.5  11.4  0.1])*phun("mm"); # layer thicknesses
TH = sum(ts); # total thickness of the plate

tolerance = 0.0001*TH

# The line load is in the negative Z direction.
q0 = 1*phun("MPa"); #    line load

# Reference deflection under the load is
wtopref = -3.789*phun("mm"); # From [1]
wbottomref = -3.789*phun("mm"); # Not given in [1]

# The reference tensile stress at the bottom of the lowest layer is
sigma11Eref = 684*phun("MPa");

# Because we model the first-quadrant quarter of the plate using
# coordinate axes centered  at the point E  the shear at the point D is
# positive instead of negative as in the benchmark where the coordinate
# system is located at the outer corner of the strip.
sigma13Dref=4.1*phun("MPa");

Refinement = 5
# We select 8 elements spanwise and 2 elements widthwise.  The overhang
# of the plate is given one element.
nL = Refinement * 1; nS = nL + Refinement * 1;

# Each layer is modeled with a single element.
nts= Refinement * ones(Int, length(angles));# number of elements per layer

xs = unique(vcat(collect(linspace(0,Lx/2,nL+1)),
    collect(linspace(Lx/2,Sx/2,nS-nL+1))))
ys = unique(vcat(collect(linspace(0,Ly/2,nL+1)),
    collect(linspace(Ly/2,Sy/2,nS-nL+1))))

fens,fes = H8compositeplatex(xs, ys, ts, nts)


# This is the material  model
MR = DeforModelRed3D
skinmaterial = MatDeforElastOrtho(MR,
    0.0, E1s, E2s, E3s,
    nu12s, nu13s, nu23s,
    G12s, G13s, G23s,
    CTE1, CTE2, CTE3)
corematerial = MatDeforElastOrtho(MR,
        0.0, E1c, E2c, E3c,
        nu12c, nu13c, nu23c,
        G12c, G13c, G23c,
        CTE1, CTE2, CTE3)

# The material coordinate system function is defined as:
function updatecs!(csmatout::FFltMat, XYZ::FFltMat, tangents::FFltMat, fe_label::FInt)
    rotmat3!(csmatout, angles[fe_label]/180.0*pi* [0.0; 0.0; 1.0]);
end

# The vvolume integrals are evaluated using this rule
gr = GaussRule(3, 2)

# We will create two regions, one for the skin,
# and one for the core.
rls = selectelem(fens, fes, label = 1)
botskinregion = FDataDict("femm"=>FEMMDeforLinearMSH8(MR,
    GeoD(subset(fes, rls), gr, CSys(3, 3, updatecs!)), skinmaterial))
rls = selectelem(fens, fes, label = 3)
topskinregion = FDataDict("femm"=>FEMMDeforLinearMSH8(MR,
    GeoD(subset(fes, rls), gr, CSys(3, 3, updatecs!)), skinmaterial))
rlc = selectelem(fens, fes, label = 2)
coreregion = FDataDict("femm"=>FEMMDeforLinearMSH8(MR,
    GeoD(subset(fes, rlc), gr, CSys(3, 3, updatecs!)), corematerial))

# File =  "Meyer_Piening_sandwich-r1.vtk"
# vtkexportmesh(File, skinregion["femm"].geod.fes.conn, fens.xyz, FinEtools.MeshExportModule.H8)
# # @async run(`"paraview.exe" $File`)
# File =  "Meyer_Piening_sandwich-r2.vtk"
# vtkexportmesh(File, coreregion["femm"].geod.fes.conn, fens.xyz, FinEtools.MeshExportModule.H8)
# @async run(`"paraview.exe" $File`)

# The essential boundary conditions are applied on the symmetry planes.
# First the plane X=0;...
lx0 = selectnode(fens, box=[0.0 0.0 -Inf Inf -Inf Inf], inflate=tolerance)
ex0 = FDataDict( "displacement"=>  0.0, "component"=> 1, "node_list"=>lx0 )
# ... and then the plane Y=0.
ly0 = selectnode(fens, box=[-Inf Inf 0.0 0.0 -Inf Inf], inflate=tolerance)
ey0 = FDataDict( "displacement"=>  0.0, "component"=> 2, "node_list"=>ly0 )
# The transverse displacement is fixed around the circumference.
lz0 = vcat(selectnode(fens, box=[Sx/2 Sx/2 -Inf Inf -Inf Inf], inflate=tolerance),
    selectnode(fens, box=[-Inf Inf Sy/2 Sy/2 -Inf Inf], inflate=tolerance))
ez0 = FDataDict( "displacement"=>  0.0, "component"=> 3, "node_list"=>lz0 )

# The traction boundary condition is applied  along rectangle in the middle of the plate.
bfes = meshboundary(fes)
# From  the entire boundary we select those quadrilaterals that lie on the plane
# Z = thickness
tl = selectelem(fens, bfes, box = [0.0 Lx/2 0 Ly/2 TH TH], inflate=tolerance)
Trac = FDataDict("traction_vector"=>vec([0.0; 0.0; -q0]),
    "femm"=>FEMMBase(GeoD(subset(bfes, tl), GaussRule(2, 2))))

modeldata = FDataDict("fens"=>fens,
 "regions"=>[botskinregion, coreregion, topskinregion],
 "essential_bcs"=>[ex0, ey0, ez0],
 "traction_bcs"=> [Trac]
 )
modeldata = AlgoDeforLinearModule.linearstatics(modeldata)

modeldata["postprocessing"] = FDataDict("file"=>"Meyer_Piening_sandwich")
modeldata = AlgoDeforLinearModule.exportdeformation(modeldata)

u = modeldata["u"]
geom = modeldata["geom"]

# The results of the displacement and stresses will be reported at
# nodes located at the appropriate points.
nbottomcenter = selectnode(fens, box=[0.0 0.0 0.0 0.0 0.0 0.0], inflate=tolerance)
ntopcenter = selectnode(fens, box=[0.0 0.0 0.0 0.0 TH TH], inflate=tolerance)
ncenterline = selectnode(fens, box=[0.0 0.0 0.0 0.0 0.0 TH], inflate=tolerance)

clo = sortperm(vec(geom.values[ncenterline, 3]))
centerz = geom.values[ncenterline[clo], 3]

conninbotskin = intersect(connectednodes(botskinregion["femm"].geod.fes), ncenterline)
connincore = intersect(connectednodes(coreregion["femm"].geod.fes), ncenterline)
connintopskin = intersect(connectednodes(topskinregion["femm"].geod.fes), ncenterline)
inbotskin = [n in conninbotskin for n in ncenterline]
incore = [n in connincore for n in ncenterline]
intopskin = [n in connintopskin for n in ncenterline]

println("")
println("Top Center deflection: $(u.values[ntopcenter, 3]/phun("mm")) [mm]")
println("Bottom Center deflection: $(u.values[nbottomcenter, 3]/phun("mm")) [mm]")

# # extrap = :extrapmean
# extrap = :extraptrendpaper
extrap = :extraptrend
inspectormeth = :averaging
# extrap = :default
# inspectormeth = :invdistance

modeldata["postprocessing"] = FDataDict("file"=>"Meyer_Piening_sandwich-sx",
    "quantity"=>:Cauchy, "component"=>1, "outputcsys"=>CSys(3),
     "inspectormethod"=>inspectormeth, "tonode"=>extrap)
modeldata = AlgoDeforLinearModule.exportstress(modeldata)
s = modeldata["postprocessing"]["exported_fields"][1]
sxbot = s.values[ncenterline[clo], 1]
s = modeldata["postprocessing"]["exported_fields"][2]
sxcore = s.values[ncenterline[clo], 1]
s = modeldata["postprocessing"]["exported_fields"][3]
sxtop = s.values[ncenterline[clo], 1]

# modeldata["postprocessing"] = FDataDict("file"=>"Meyer_Piening_sandwich-sxz",
# "quantity"=>:Cauchy, "component"=>5, "outputcsys"=>CSys(3),
#  "inspectormethod"=>inspectormeth, "tonode"=>extrap)
# modeldata = AlgoDeforLinearModule.exportstress(modeldata)
# s = modeldata["postprocessing"]["exported_fields"][1]

zs = []
sxs = []
for (j, z) in enumerate(centerz)
    if inbotskin[j]
        push!(zs, z)
        push!(sxs, sxbot[j])
    end
end
for (j, z) in enumerate(centerz)
    if incore[j]
        push!(zs, z)
        push!(sxs, sxcore[j])
    end
end
for (j, z) in enumerate(centerz)
    if intopskin[j]
        push!(zs, z)
        push!(sxs, sxtop[j])
    end
end
println("$(zs)")
df = DataFrame(zs=vec(zs), sx=vec(sxs)/phun("MPa"))

File = "Meyer_Piening_sandwich-sx-$(extrap).CSV"
CSV.write(File, df)

@async run(`"paraview.exe" $File`)

println("Done")
true

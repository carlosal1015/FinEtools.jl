using FinEtools

println("LE1NAFEMS, plane stress.")
t0 = time()

E = 210e3*phun("MEGA*PA");# 210e3 MPa
nu = 0.3;
p = 10*phun("MEGA*PA");# 10 MPA Outward pressure on the outside ellipse
sigma_yD= 92.7*phun("MEGA*PA");# tensile stress at [2.0, 0.0] meters
Radius= 1.0*phun("m")
n=20; # number of elements per side
tolerance=1.0/n/1000.;#Geometrical tolerance

fens,fes = Q8block(1.0,pi/2, n, n*2)

bdryfes = meshboundary(fes);
icl = selectelem(fens, bdryfes, box=[1.0,1.0,0.0,pi/2],inflate=tolerance);
for i=1:count(fens)
    t=fens.xyz[i,1]; a=fens.xyz[i,2];
    fens.xyz[i,:]=[(t*3.25+(1-t)*2)*cos(a) (t*2.75+(1-t)*1)*sin(a)];
end


geom = NodalField(fens.xyz)
u = NodalField(zeros(size(fens.xyz,1),2)) # displacement field

l1 =selectnode(fens; box=[0.0 Inf 0.0 0.0], inflate = tolerance)
setebc!(u,l1,true,2,0.0)
l1 =selectnode(fens; box=[0.0 0.0 0.0 Inf], inflate = tolerance)
setebc!(u,l1,true,1,0.0)

applyebc!(u)
numberdofs!(u)

el1femm =  FEMMBase(IntegData(subset(bdryfes,icl), GaussRule(1, 3)))
function pfun(forceout::FFltVec, x::FFltMat, J::FFltMat, l::FInt)
    pt= [2.75/3.25*x[1] 3.25/2.75*x[2]]
    copy!(forceout, vec(p*pt/norm(pt)))
    return forceout
end
fi = ForceIntensity(FFlt, 2, pfun);
F2= distribloads(el1femm, geom, u, fi, 2);


material=MatDeforElastIso(MR, E, nu)
MR = DeforModelRed2DStress
femm = FEMMDeforLinear(MR, IntegData(fes, GaussRule(2, 3)), material)

K =stiffness(femm, geom, u)
K=cholfact(K)
U=  K\(F2)
scattersysvec!(u,U[:])

nl=selectnode(fens, box=[2.0,2.0,0.0,0.0],inflate=tolerance);
thecorneru=zeros(FFlt,1,2)
gathervalues_asmat!(u,thecorneru,nl);
thecorneru=thecorneru/phun("mm")
println("$(time()-t0) [s];  displacement =$(thecorneru) [MM] as compared to reference [-0.10215,0] [MM]")

fld= fieldfromintegpoints(femm, geom, u, :Cauchy, 2)
println("  Target stress: $(fld.values[nl][1]/phun("MEGA*PA")) compared to $(sigma_yD/phun("MEGA*PA"))")

using FinEtools.MeshExportModule

File =  "a.vtk"
vtkexportmesh(File, fes.conn, geom.values,
               FinEtools.MeshExportModule.Q8;
               vectors=[("u", u.values)], scalars=[("sigy", fld.values)])
@async run(`"paraview.exe" $File`)
true

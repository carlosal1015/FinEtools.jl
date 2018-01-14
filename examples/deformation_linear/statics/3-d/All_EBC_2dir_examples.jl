module All_EBC_2dir_examples
using FinEtools
using FinEtools.AlgoDeforLinearModule
using FinEtools.MeshUtilModule
using FinEtools.AlgoBaseModule

displacement_fun_x(x) = dot([0.0, 0.01, 0.0, 0.0, 0.0, -0.001, 0.0, 0.002, 0.0, 0.0], [1.0, x[1], x[2], x[3], x[1] * x[2], x[1] * x[3], x[2] * x[3], x[1]^2, x[2]^2, x[3]^2])
displacement_fun_y(x) = dot([0.0, 0.0, 0.003, 0.0, 0.03, 0.0, 0.007, 0.0, 0.008, -0.007], [1.0, x[1], x[2], x[3], x[1] * x[2], x[1] * x[3], x[2] * x[3], x[1]^2, x[2]^2, x[3]^2])
displacement_fun_z(x) = dot([0.0, 0.0, 0.0, 0.007, 0.008, 0.0, -0.05, 0.0, 0.0, 0.0], [1.0, x[1], x[2], x[3], x[1] * x[2], x[1] * x[3], x[2] * x[3], x[1]^2, x[2]^2, x[3]^2])

function All_EBC_2dir_MST10_conv()
    elementtag = "MST10"
    println("""
    Fiber-reinforced block: $(elementtag)
    """)
    
    for (extrap, nodevalmeth) = zip([:extrapmean, :extraptrend, :default], [:averaging, :averaging, :invdistance])
        filebase = "All_EBC_2dir_$(elementtag)_$(extrap)"
        modeldatasequence = FDataDict[]
        for Refinement = [1, 2, 4, 8, 16]
            
            # Orthotropic material 
            E1 = 2.0e9*phun("Pa"); E2 = 2.0e9*phun("Pa"); E3 = 1.0e9*phun("Pa");
            G12 = 0.2e9*phun("Pa");  G13 = G12; G23 = 0.2e9*phun("Pa")
            nu12 = nu13 = nu23 =  0.25;
            # Coefficients of thermal expansion
            CTE1 = CTE2 = CTE3 = 0.0 
            # This is the material  model
            MR = DeforModelRed3D
            material = MatDeforElastOrtho(MR, 0.0, E1, E2, E3, nu12, nu13, nu23, G12, G13, G23, CTE1, CTE2, CTE3)
            # dimensions of the plate
            a = 70.0*phun("mm"); 
            b = 100.0*phun("mm"); 
            t = 50.0*phun("mm"); 
            # Transverse loading
            q0 = 1000.0*phun("Pa")
            
            # Here we define the layout and the thicknesses of the layers.
            angles = vec([45.0]);
            nLayers = length(angles)
            ts = t/nLayers * ones(nLayers); # layer thicknesses
            
            tolerance = 0.0001*t
            
            # Select how fine the mesh should be
            nts= Refinement * ones(Int, nLayers);# number of elements per layer
            tnts = sum(nts)
            na, nb = tnts, tnts;
            
            xs = collect(linspace(0.0, a, na+1))
            ys = collect(linspace(0.0, b, nb+1))
            fens,fes = T10layeredplatex(xs, ys, ts, nts)
            println("Mesh: na, nb, nts = $na, $nb, $nts")
            println("count(fens) = $(count(fens))")
            
            # The material coordinate system function is defined as:
            function updatecs!(csmatout::FFltMat, XYZ::FFltMat, tangents::FFltMat, fe_label::FInt)
                rotmat3!(csmatout, angles[fe_label]/180.0*pi* [0.0; 0.0; 1.0]);
            end
            
            # The volume integrals are evaluated using this rule
            gr = SimplexRule(3, 4)
            
            # We will create one region per layer
            regions = FDataDict[]
            for layer = 1:nLayers
                rls = selectelem(fens, fes, label =  layer)
                push!(regions, FDataDict("femm"=>FEMMDeforLinearMST10(MR, IntegData(subset(fes, rls), gr), CSys(3, 3, updatecs!), material)))
            end
            
            # The essential boundary conditions: the entire surface
            bfes = meshboundary(fes)
            lx0 = connectednodes(bfes)
            eclamped1 = FDataDict("displacement"=> displacement_fun_x, "component"=> 1, "node_list"=>lx0)
            eclamped2 = FDataDict("displacement"=> displacement_fun_y, "component"=> 2, "node_list"=>lx0)
            eclamped3 = FDataDict("displacement"=> displacement_fun_z, "component"=> 3, "node_list"=>lx0)
            
            modeldata = FDataDict("fens"=>fens, "regions"=>regions, "essential_bcs"=>[eclamped1, eclamped2, eclamped3])
            modeldata = AlgoDeforLinearModule.linearstatics(modeldata)
            
            # modeldata["postprocessing"] = FDataDict("file"=>filebase * "-u")
            # modeldata = AlgoDeforLinearModule.exportdeformation(modeldata)
            
            u = modeldata["u"]
            geom = modeldata["geom"]
            
            #  Compute  all stresses
            modeldata["postprocessing"] = FDataDict("file"=>filebase * "-s", "quantity"=>:Cauchy, "component"=>collect(1:6), "outputcsys"=>CSys(3), "nodevalmethod"=>nodevalmeth, "reportat"=>extrap)
            modeldata = AlgoDeforLinearModule.exportstress(modeldata)
            
            modeldata["elementsize"] = t/Refinement
            modeldata["geometricaltolerance"] = tolerance
            push!(modeldatasequence, modeldata)
        end # for refinement
        
        println("")
        println("Stress RMS error")
        for md = modeldatasequence
            md["targetfields"] = [e["field"] for e in md["postprocessing"]["exported"]]
        end
        elementsizes, errornorms, p = AlgoBaseModule.evalconvergencestudy(modeldatasequence)
        
        println("Normalized Approximate Error = $(errornorms)")
        
        f = log.(vec(errornorms))
        A = hcat(log.(vec(elementsizes[1:end-1])), ones(size(f)))
        p = A \ f
        println("Linear log-log fit: p = $(p)")
        
        csvFile = filebase * "_Stress" * ".CSV"
        savecsv(csvFile,
        elementsizes=vec(elementsizes[1:end-1]),
        elementsizes2=vec(elementsizes[1:end-1].^2),
        elementsizes3=vec(elementsizes[1:end-1].^3),
        errornorms=vec(errornorms)
        )
        println("Wrote $csvFile")
        
        println("")
        println("Displacement RMS error")
        for md = modeldatasequence
            md["targetfields"] = [md["u"] for r in md["regions"]]
        end
        elementsizes, errornorms, p = AlgoBaseModule.evalconvergencestudy(modeldatasequence)
        
        println("Normalized Approximate Error = $(errornorms)")
        
        f = log.(vec(errornorms))
        A = hcat(log.(vec(elementsizes[1:end-1])), ones(size(f)))
        p = A \ f
        println("Linear log-log fit: p = $(p)")
        
        csvFile = filebase * "_Displ" * ".CSV"
        savecsv(csvFile,
        elementsizes=vec(elementsizes[1:end-1]),
        elementsizes2=vec(elementsizes[1:end-1].^2),
        elementsizes3=vec(elementsizes[1:end-1].^3),
        errornorms=vec(errornorms)
        )
        println("Wrote $csvFile")
        
        # @async run(`"paraview.exe" $csvFile`)
    end # extrap
    println("Done")
    
end # All_EBC_2dir_MST10_conv

function All_EBC_2dir_MSH8_conv()
    elementtag = "MSH8"
    println("""
    Fiber-reinforced block: $(elementtag)
    """)
    
    for (extrap, nodevalmeth) = zip([:extrapmean, :extraptrend, :default], [:averaging, :averaging, :invdistance])
        filebase = "All_EBC_2dir_$(elementtag)_$(extrap)"
        modeldatasequence = FDataDict[]
        for Refinement = [1, 2, 4, 8, 16]
            
            # Orthotropic material 
            E1 = 2.0e9*phun("Pa"); E2 = 2.0e9*phun("Pa"); E3 = 1.0e9*phun("Pa");
            G12 = 0.2e9*phun("Pa");  G13 = G12; G23 = 0.2e9*phun("Pa")
            nu12 = nu13 = nu23 =  0.25;
            # Coefficients of thermal expansion
            CTE1 = CTE2 = CTE3 = 0.0 
            # This is the material  model
            MR = DeforModelRed3D
            material = MatDeforElastOrtho(MR, 0.0, E1, E2, E3, nu12, nu13, nu23, G12, G13, G23, CTE1, CTE2, CTE3)
            # dimensions of the plate
            a = 70.0*phun("mm"); 
            b = 100.0*phun("mm"); 
            t = 50.0*phun("mm"); 
            # Transverse loading
            q0 = 1000.0*phun("Pa")
            
            # Here we define the layout and the thicknesses of the layers.
            angles = vec([45.0]);
            nLayers = length(angles)
            ts = t/nLayers * ones(nLayers); # layer thicknesses
            
            tolerance = 0.0001*t
            
            # Select how fine the mesh should be
            nts= Refinement * ones(Int, nLayers);# number of elements per layer
            tnts = sum(nts)
            na, nb = tnts, tnts;
            
            xs = collect(linspace(0.0, a, na+1))
            ys = collect(linspace(0.0, b, nb+1))
            fens,fes = H8layeredplatex(xs, ys, ts, nts)
            println("Mesh: na, nb, nts = $na, $nb, $nts")
            println("count(fens) = $(count(fens))")
            
            # The material coordinate system function is defined as:
            function updatecs!(csmatout::FFltMat, XYZ::FFltMat, tangents::FFltMat, fe_label::FInt)
                rotmat3!(csmatout, angles[fe_label]/180.0*pi* [0.0; 0.0; 1.0]);
            end
            
            # The volume integrals are evaluated using this rule
            gr = GaussRule(3, 2)
            
            # We will create one region per layer
            regions = FDataDict[]
            for layer = 1:nLayers
                rls = selectelem(fens, fes, label =  layer)
                push!(regions, FDataDict("femm"=>FEMMDeforLinearMSH8(MR, IntegData(subset(fes, rls), gr), CSys(3, 3, updatecs!), material)))
            end
            
            # The essential boundary conditions: the entire surface
            bfes = meshboundary(fes)
            lx0 = connectednodes(bfes)
            eclamped1 = FDataDict("displacement"=> displacement_fun_x, "component"=> 1, "node_list"=>lx0)
            eclamped2 = FDataDict("displacement"=> displacement_fun_y, "component"=> 2, "node_list"=>lx0)
            eclamped3 = FDataDict("displacement"=> displacement_fun_z, "component"=> 3, "node_list"=>lx0)
            
            modeldata = FDataDict("fens"=>fens, "regions"=>regions, "essential_bcs"=>[eclamped1, eclamped2, eclamped3])
            modeldata = AlgoDeforLinearModule.linearstatics(modeldata)
            
            # modeldata["postprocessing"] = FDataDict("file"=>filebase * "-u")
            # modeldata = AlgoDeforLinearModule.exportdeformation(modeldata)
            
            u = modeldata["u"]
            geom = modeldata["geom"]
            
            #  Compute  all stresses
            modeldata["postprocessing"] = FDataDict("file"=>filebase * "-s", "quantity"=>:Cauchy, "component"=>collect(1:6), "outputcsys"=>CSys(3), "nodevalmethod"=>nodevalmeth, "reportat"=>extrap)
            modeldata = AlgoDeforLinearModule.exportstress(modeldata)
            
            modeldata["elementsize"] = t/Refinement
            modeldata["geometricaltolerance"] = tolerance
            push!(modeldatasequence, modeldata)
        end # for refinement
        
        println("")
        println("Stress RMS error")
        for md = modeldatasequence
            md["targetfields"] = [e["field"] for e in md["postprocessing"]["exported"]]
        end
        elementsizes, errornorms, p = AlgoBaseModule.evalconvergencestudy(modeldatasequence)
        
        println("Normalized Approximate Error = $(errornorms)")
        
        f = log.(vec(errornorms))
        A = hcat(log.(vec(elementsizes[1:end-1])), ones(size(f)))
        p = A \ f
        println("Linear log-log fit: p = $(p)")
        
        csvFile = filebase * "_Stress" * ".CSV"
        savecsv(csvFile,
        elementsizes=vec(elementsizes[1:end-1]),
        elementsizes2=vec(elementsizes[1:end-1].^2),
        elementsizes3=vec(elementsizes[1:end-1].^3),
        errornorms=vec(errornorms)
        )
        println("Wrote $csvFile")
        
        println("")
        println("Displacement RMS error")
        for md = modeldatasequence
            md["targetfields"] = [md["u"] for r in md["regions"]]
        end
        elementsizes, errornorms, p = AlgoBaseModule.evalconvergencestudy(modeldatasequence)
        
        println("Normalized Approximate Error = $(errornorms)")
        
        f = log.(vec(errornorms))
        A = hcat(log.(vec(elementsizes[1:end-1])), ones(size(f)))
        p = A \ f
        println("Linear log-log fit: p = $(p)")
        
        csvFile = filebase * "_Displ" * ".CSV"
        savecsv(csvFile,
        elementsizes=vec(elementsizes[1:end-1]),
        elementsizes2=vec(elementsizes[1:end-1].^2),
        elementsizes3=vec(elementsizes[1:end-1].^3),
        errornorms=vec(errornorms)
        )
        println("Wrote $csvFile")
        
        # @async run(`"paraview.exe" $csvFile`)
    end # extrap
    println("Done")
    
end # All_EBC_2dir_MSH8_conv

function All_EBC_2dir_T10_conv()
    elementtag = "T10"
    println("""
    Fiber-reinforced block: $(elementtag)
    """)
    
    for (extrap, nodevalmeth) = zip([:default], [:invdistance])
        filebase = "All_EBC_2dir_$(elementtag)_$(extrap)"
        modeldatasequence = FDataDict[]
        for Refinement = [1, 2, 4, 8, 16]
            
            # Orthotropic material 
            E1 = 2.0e9*phun("Pa"); E2 = 2.0e9*phun("Pa"); E3 = 1.0e9*phun("Pa");
            G12 = 0.2e9*phun("Pa");  G13 = G12; G23 = 0.2e9*phun("Pa")
            nu12 = nu13 = nu23 =  0.25;
            # Coefficients of thermal expansion
            CTE1 = CTE2 = CTE3 = 0.0 
            # This is the material  model
            MR = DeforModelRed3D
            material = MatDeforElastOrtho(MR, 0.0, E1, E2, E3, nu12, nu13, nu23, G12, G13, G23, CTE1, CTE2, CTE3)
            # dimensions of the plate
            a = 70.0*phun("mm"); 
            b = 100.0*phun("mm"); 
            t = 50.0*phun("mm"); 
            # Transverse loading
            q0 = 1000.0*phun("Pa")
            
            # Here we define the layout and the thicknesses of the layers.
            angles = vec([45.0]);
            nLayers = length(angles)
            ts = t/nLayers * ones(nLayers); # layer thicknesses
            
            tolerance = 0.0001*t
            
            # Select how fine the mesh should be
            nts= Refinement * ones(Int, nLayers);# number of elements per layer
            tnts = sum(nts)
            na, nb = tnts, tnts;
            
            xs = collect(linspace(0.0, a, na+1))
            ys = collect(linspace(0.0, b, nb+1))
            fens,fes = T10layeredplatex(xs, ys, ts, nts)
            println("Mesh: na, nb, nts = $na, $nb, $nts")
            println("count(fens) = $(count(fens))")
            
            # The material coordinate system function is defined as:
            function updatecs!(csmatout::FFltMat, XYZ::FFltMat, tangents::FFltMat, fe_label::FInt)
                rotmat3!(csmatout, angles[fe_label]/180.0*pi* [0.0; 0.0; 1.0]);
            end
            
            # The volume integrals are evaluated using this rule
            gr = SimplexRule(3, 4)
            
            # We will create one region per layer
            regions = FDataDict[]
            for layer = 1:nLayers
                rls = selectelem(fens, fes, label =  layer)
                push!(regions, FDataDict("femm"=>FEMMDeforLinear(MR, IntegData(subset(fes, rls), gr), CSys(3, 3, updatecs!), material)))
            end
            
            # The essential boundary conditions: the entire surface
            bfes = meshboundary(fes)
            lx0 = connectednodes(bfes)
            eclamped1 = FDataDict("displacement"=> displacement_fun_x, "component"=> 1, "node_list"=>lx0)
            eclamped2 = FDataDict("displacement"=> displacement_fun_y, "component"=> 2, "node_list"=>lx0)
            eclamped3 = FDataDict("displacement"=> displacement_fun_z, "component"=> 3, "node_list"=>lx0)
            
            modeldata = FDataDict("fens"=>fens, "regions"=>regions, "essential_bcs"=>[eclamped1, eclamped2, eclamped3])
            modeldata = AlgoDeforLinearModule.linearstatics(modeldata)
            
            # modeldata["postprocessing"] = FDataDict("file"=>filebase * "-u")
            # modeldata = AlgoDeforLinearModule.exportdeformation(modeldata)
            
            u = modeldata["u"]
            geom = modeldata["geom"]
            
            #  Compute  all stresses
            modeldata["postprocessing"] = FDataDict("file"=>filebase * "-s", "quantity"=>:Cauchy, "component"=>collect(1:6), "outputcsys"=>CSys(3), "nodevalmethod"=>nodevalmeth, "reportat"=>extrap)
            modeldata = AlgoDeforLinearModule.exportstress(modeldata)
            
            modeldata["elementsize"] = t/Refinement
            modeldata["geometricaltolerance"] = tolerance
            push!(modeldatasequence, modeldata)
        end # for refinement
        
        println("")
        println("Stress RMS error")
        for md = modeldatasequence
            md["targetfields"] = [e["field"] for e in md["postprocessing"]["exported"]]
        end
        elementsizes, errornorms, p = AlgoBaseModule.evalconvergencestudy(modeldatasequence)
        
        println("Normalized Approximate Error = $(errornorms)")
        
        f = log.(vec(errornorms))
        A = hcat(log.(vec(elementsizes[1:end-1])), ones(size(f)))
        p = A \ f
        println("Linear log-log fit: p = $(p)")
        
        csvFile = filebase * "_Stress" * ".CSV"
        savecsv(csvFile,
        elementsizes=vec(elementsizes[1:end-1]),
        elementsizes2=vec(elementsizes[1:end-1].^2),
        elementsizes3=vec(elementsizes[1:end-1].^3),
        errornorms=vec(errornorms)
        )
        println("Wrote $csvFile")
        
        println("")
        println("Displacement RMS error")
        for md = modeldatasequence
            md["targetfields"] = [md["u"] for r in md["regions"]]
        end
        elementsizes, errornorms, p = AlgoBaseModule.evalconvergencestudy(modeldatasequence)
        
        println("Normalized Approximate Error = $(errornorms)")
        
        f = log.(vec(errornorms))
        A = hcat(log.(vec(elementsizes[1:end-1])), ones(size(f)))
        p = A \ f
        println("Linear log-log fit: p = $(p)")
        
        csvFile = filebase * "_Displ" * ".CSV"
        savecsv(csvFile,
        elementsizes=vec(elementsizes[1:end-1]),
        elementsizes2=vec(elementsizes[1:end-1].^2),
        elementsizes3=vec(elementsizes[1:end-1].^3),
        errornorms=vec(errornorms)
        )
        println("Wrote $csvFile")
        
        # @async run(`"paraview.exe" $csvFile`)
    end # extrap
    println("Done")
    
end # All_EBC_2dir_T10_conv

function All_EBC_2dir_H8_conv()
    elementtag = "H8"
    println("""
    Fiber-reinforced block: $(elementtag)
    """)
    
    for (extrap, nodevalmeth) = zip([:default], [:invdistance])
        filebase = "All_EBC_2dir_$(elementtag)_$(extrap)"
        modeldatasequence = FDataDict[]
        for Refinement = [1, 2, 4, 8, 16]
            
            # Orthotropic material 
            E1 = 2.0e9*phun("Pa"); E2 = 2.0e9*phun("Pa"); E3 = 1.0e9*phun("Pa");
            G12 = 0.2e9*phun("Pa");  G13 = G12; G23 = 0.2e9*phun("Pa")
            nu12 = nu13 = nu23 =  0.25;
            # Coefficients of thermal expansion
            CTE1 = CTE2 = CTE3 = 0.0 
            # This is the material  model
            MR = DeforModelRed3D
            material = MatDeforElastOrtho(MR, 0.0, E1, E2, E3, nu12, nu13, nu23, G12, G13, G23, CTE1, CTE2, CTE3)
            # dimensions of the plate
            a = 70.0*phun("mm"); 
            b = 100.0*phun("mm"); 
            t = 50.0*phun("mm"); 
            # Transverse loading
            q0 = 1000.0*phun("Pa")
            
            # Here we define the layout and the thicknesses of the layers.
            angles = vec([45.0]);
            nLayers = length(angles)
            ts = t/nLayers * ones(nLayers); # layer thicknesses
            
            tolerance = 0.0001*t
            
            # Select how fine the mesh should be
            nts= Refinement * ones(Int, nLayers);# number of elements per layer
            tnts = sum(nts)
            na, nb = tnts, tnts;
            
            xs = collect(linspace(0.0, a, na+1))
            ys = collect(linspace(0.0, b, nb+1))
            fens,fes = H8layeredplatex(xs, ys, ts, nts)
            println("Mesh: na, nb, nts = $na, $nb, $nts")
            println("count(fens) = $(count(fens))")
            
            # The material coordinate system function is defined as:
            function updatecs!(csmatout::FFltMat, XYZ::FFltMat, tangents::FFltMat, fe_label::FInt)
                rotmat3!(csmatout, angles[fe_label]/180.0*pi* [0.0; 0.0; 1.0]);
            end
            
            # The volume integrals are evaluated using this rule
            gr = GaussRule(3, 2)
            
            # We will create one region per layer
            regions = FDataDict[]
            for layer = 1:nLayers
                rls = selectelem(fens, fes, label =  layer)
                push!(regions, FDataDict("femm"=>FEMMDeforLinear(MR, IntegData(subset(fes, rls), gr), CSys(3, 3, updatecs!), material)))
            end
            
            # The essential boundary conditions: the entire surface
            bfes = meshboundary(fes)
            lx0 = connectednodes(bfes)
            eclamped1 = FDataDict("displacement"=> displacement_fun_x, "component"=> 1, "node_list"=>lx0)
            eclamped2 = FDataDict("displacement"=> displacement_fun_y, "component"=> 2, "node_list"=>lx0)
            eclamped3 = FDataDict("displacement"=> displacement_fun_z, "component"=> 3, "node_list"=>lx0)
            
            modeldata = FDataDict("fens"=>fens, "regions"=>regions, "essential_bcs"=>[eclamped1, eclamped2, eclamped3])
            modeldata = AlgoDeforLinearModule.linearstatics(modeldata)
            
            # modeldata["postprocessing"] = FDataDict("file"=>filebase * "-u")
            # modeldata = AlgoDeforLinearModule.exportdeformation(modeldata)
            
            u = modeldata["u"]
            geom = modeldata["geom"]
            
            #  Compute  all stresses
            modeldata["postprocessing"] = FDataDict("file"=>filebase * "-s", "quantity"=>:Cauchy, "component"=>collect(1:6), "outputcsys"=>CSys(3), "nodevalmethod"=>nodevalmeth, "reportat"=>extrap)
            modeldata = AlgoDeforLinearModule.exportstress(modeldata)
            
            modeldata["elementsize"] = t/Refinement
            modeldata["geometricaltolerance"] = tolerance
            push!(modeldatasequence, modeldata)
        end # for refinement
        
        println("")
        println("Stress RMS error")
        for md = modeldatasequence
            md["targetfields"] = [e["field"] for e in md["postprocessing"]["exported"]]
        end
        elementsizes, errornorms, p = AlgoBaseModule.evalconvergencestudy(modeldatasequence)
        
        println("Normalized Approximate Error = $(errornorms)")
        
        f = log.(vec(errornorms))
        A = hcat(log.(vec(elementsizes[1:end-1])), ones(size(f)))
        p = A \ f
        println("Linear log-log fit: p = $(p)")
        
        csvFile = filebase * "_Stress" * ".CSV"
        savecsv(csvFile,
        elementsizes=vec(elementsizes[1:end-1]),
        elementsizes2=vec(elementsizes[1:end-1].^2),
        elementsizes3=vec(elementsizes[1:end-1].^3),
        errornorms=vec(errornorms)
        )
        println("Wrote $csvFile")
        
        println("")
        println("Displacement RMS error")
        for md = modeldatasequence
            md["targetfields"] = [md["u"] for r in md["regions"]]
        end
        elementsizes, errornorms, p = AlgoBaseModule.evalconvergencestudy(modeldatasequence)
        
        println("Normalized Approximate Error = $(errornorms)")
        
        f = log.(vec(errornorms))
        A = hcat(log.(vec(elementsizes[1:end-1])), ones(size(f)))
        p = A \ f
        println("Linear log-log fit: p = $(p)")
        
        csvFile = filebase * "_Displ" * ".CSV"
        savecsv(csvFile,
        elementsizes=vec(elementsizes[1:end-1]),
        elementsizes2=vec(elementsizes[1:end-1].^2),
        elementsizes3=vec(elementsizes[1:end-1].^3),
        errornorms=vec(errornorms)
        )
        println("Wrote $csvFile")
        
        # @async run(`"paraview.exe" $csvFile`)
    end # extrap
    println("Done")
    
end # All_EBC_2dir_H8_conv

function allrun()
    println("#####################################################") 
    println("# All_EBC_2dir_MST10_conv ")
    All_EBC_2dir_MST10_conv()
    println("#####################################################") 
    println("# All_EBC_2dir_MSH8_conv ")
    All_EBC_2dir_MSH8_conv()
    println("#####################################################") 
    println("# All_EBC_2dir_T10_conv ")
    All_EBC_2dir_T10_conv()
    println("#####################################################") 
    println("# All_EBC_2dir_H8_conv ")
    All_EBC_2dir_H8_conv()
    return true
end # function allrun

end # module Pagano_examples

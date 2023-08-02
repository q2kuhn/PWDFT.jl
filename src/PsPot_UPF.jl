using SpecialFunctions: sphericalbesselj, erf

function is_using_extension_upf(filename::String)
    fil_ext = lowercase(split(filename, ".")[end])
    # We also allow upf2 as a valid extension file UPF
    return (fil_ext == "upf") || (fil_ext == "upf2")
end


struct PsPot_UPF <: AbstractPsPot
    pspfile::String
    atsymb::String
    zval::Float64
    #
    is_nlcc::Bool
    is_ultrasoft::Bool
    is_paw::Bool
    # Radial vars
    Nr::Int64
    r::Array{Float64,1}
    rab::Array{Float64,1}
    dx::Float64
    rmin::Float64
    rmax::Float64
    zmesh::Float64
    #
    V_local::Array{Float64,1}
    # Projectors
    Nproj::Int64
    proj_l::Array{Int64,1}
    rcut_l::Array{Float64,1}
    kkbeta::Int64
    proj_func::Array{Float64,2}
    Dion::Array{Float64,2}
    # From PsPot_GTH (may be remove this)
    h::Array{Float64,3}   # l,1:3,1:3
    lmax::Int64           # l = 0, 1, 2, 3 (s, p, d, f)
    Nproj_l::Array{Int64,1}  # originally 0:3
    # used in PAW
    lmax_rho::Int64
    # Core density
    rho_atc::Vector{Float64}
    # Augmentation stuffs
    nqf::Int64
    nqlc::Int64
    qqq::Array{Float64,2}
    q_with_l::Bool
    qfuncl::Array{Float64,3}
    #
    Nchi::Int64 # different from Nwfc
    chi::Array{Float64,2}
    lchi::Array{Int64,1}
    occ_chi::Array{Float64,1}
    rhoatom::Array{Float64,1}
    #
    paw_data::Union{PAWData_UPF,Nothing}
end

#
# The constructor
#
function PsPot_UPF( upf_file::String )
 
    # Probably we should check that the extension of the file is UPF

    xdoc = LightXML.parse_file(upf_file)

    # get the root element
    xroot = LightXML.root(xdoc)  # an instance of XMLElement
    
    #
    # Read some information from header
    #
    pp_header = LightXML.get_elements_by_tagname(xroot, "PP_HEADER")
    atsymb = LightXML.attributes_dict(pp_header[1])["element"]
    zval = Int64(parse(Float64, LightXML.attributes_dict(pp_header[1])["z_valence"]))
    lmax = parse(Int64, LightXML.attributes_dict(pp_header[1])["l_max"])
    Nr = parse(Int64,LightXML.attributes_dict(pp_header[1])["mesh_size"])
    # Data generated by atompaw seems to have wrong mesh_size information in the header
    # I solved this problem by modifying the UPF file manually.

    str1 = LightXML.attributes_dict(pp_header[1])["core_correction"]
    if str1 == "F"  # XXX F is not parsed as False
        is_nlcc = false
    elseif str1 == "T"
        is_nlcc = true
    else
        is_nlcc = parse(Bool, str1)
    end

    str1 = LightXML.attributes_dict(pp_header[1])["is_ultrasoft"]
    if str1 == "F"  # XXX F is not parsed as False
        is_ultrasoft = false
    elseif str1 == "T"
        is_ultrasoft = true
    else
        is_ultrasoft = parse(Bool, str1)
    end

    str1 = LightXML.attributes_dict(pp_header[1])["is_paw"]
    if str1 == "F"  # XXX F is not parsed as False
        is_paw = false
    elseif str1 == "T"
        is_paw = true
    else
        is_paw = parse(Bool, str1)
    end

    if is_ultrasoft || is_paw
        lmax_rho = parse(Int64, LightXML.attributes_dict(pp_header[1])["l_max_rho"])
    else
        lmax_rho = -1
    end

    #
    # Read radial mesh information: r and rab
    #
    pp_mesh = LightXML.get_elements_by_tagname(xroot, "PP_MESH")
    pp_r = LightXML.get_elements_by_tagname(pp_mesh[1], "PP_R")
    pp_r_str = LightXML.content(pp_r[1])
    pp_r_str = replace(pp_r_str, "\n" => " ")
    spl_str = split(pp_r_str, keepempty=false)

    # Ugh... some UPF does not have these variables
    # Example: ONCV pseudopotentials
    rmesh_dict = LightXML.attributes_dict(pp_mesh[1])
    dx = 0.0
    if haskey(rmesh_dict, "dx")
        dx = parse(Float64, rmesh_dict["dx"])
    end

    xmin = 0.0
    if haskey(rmesh_dict, "xmin")
        xmin = parse(Float64, rmesh_dict["xmin"])
    end

    rmax = 0.0
    if haskey(rmesh_dict, "rmax")
        rmax = parse(Float64, rmesh_dict["rmax"])
    end

    zmesh = 0.0
    if haskey(rmesh_dict, "zmesh")
        zmesh = parse(Float64, rmesh_dict["zmesh"])
    end

    # These are used in PAW cases
    # I assume that these variables are available in the PAW pseudotentials
    # TODO: Probably only read these in case of PAW pseudopotential


    @assert(length(spl_str) == Nr)

    r = zeros(Float64, Nr)
    for i in 1:Nr
        r[i] = parse(Float64, spl_str[i])
    end

    pp_rab = LightXML.get_elements_by_tagname(pp_mesh[1], "PP_RAB")
    pp_rab_str = LightXML.content(pp_rab[1])
    pp_rab_str = replace(pp_rab_str, "\n" => " ")
    spl_str = split(pp_rab_str, keepempty=false)

    @assert(length(spl_str) == Nr)

    rab = zeros(Float64, Nr)
    for i in 1:Nr
        rab[i] = parse(Float64, spl_str[i])
    end

    #
    # Core correction
    #
    if is_nlcc
        rho_atc = zeros(Float64,Nr)
        pp_nlcc = LightXML.get_elements_by_tagname(xroot, "PP_NLCC")
        pp_nlcc_str = LightXML.content(pp_nlcc[1])
        pp_nlcc_str = replace(pp_nlcc_str, "\n" => " ")
        spl_str = split(pp_nlcc_str, keepempty=false)
        for i in 1:Nr
            rho_atc[i] = parse(Float64,spl_str[i])
        end
    else
        rho_atc = zeros(Float64,1)
    end

    #
    # Local potential
    #
    pp_local = LightXML.get_elements_by_tagname(xroot, "PP_LOCAL")
    pp_local_str = LightXML.content(pp_local[1])
    pp_local_str = replace(pp_local_str, "\n" => " ")
    spl_str = split(pp_local_str, keepempty=false)

    @assert(length(spl_str) == Nr)

    V_local = zeros(Float64, Nr)
    for i in 1:Nr
        V_local[i] = parse(Float64, spl_str[i])*0.5 # convert to Hartree
    end

    #
    # Nonlocal projector
    #
    pp_nonlocal = LightXML.get_elements_by_tagname(xroot, "PP_NONLOCAL")
    Nproj = parse(Int64,LightXML.attributes_dict(pp_header[1])["number_of_proj"])
    proj_func = zeros(Float64,Nr,Nproj)
    proj_l = zeros(Int64,Nproj)
    rcut_l = zeros(Float64,Nproj)
    kbeta = zeros(Int64,Nproj) # cutoff radius index (of radial mesh array)
    for iprj in 1:Nproj
        pp_beta = LightXML.get_elements_by_tagname(pp_nonlocal[1], "PP_BETA."*string(iprj))
        #
        proj_l[iprj] = parse( Int64, LightXML.attributes_dict(pp_beta[1])["angular_momentum"] )
        kbeta[iprj] = parse( Int64, LightXML.attributes_dict(pp_beta[1])["cutoff_radius_index"] )
        # we get rcut by accessing the kbeta[iprj]-th element of radial mesh
        rcut_l[iprj] = r[kbeta[iprj]]
        #
        pp_beta_str = LightXML.content(pp_beta[1])
        pp_beta_str = replace(pp_beta_str, "\n" => " ")
        spl_str = split(pp_beta_str, keepempty=false)
        for i in 1:Nr
            proj_func[i,iprj] = parse(Float64,spl_str[i]) #*0.5 # Convert to Hartree
        end
    end

    # Read PAW early
    if is_paw
        paw_data = PAWData_UPF(xroot, r, lmax, Nproj)
    else
        paw_data = nothing
    end

    # Used in USPP, kkbeta: for obtaining maximum rcut
    if length(kbeta) > 0
        kkbeta = maximum(kbeta)
    else
        kkbeta = 0
    end

    # For PAW, augmentation charge may extend a bit further:
    if is_paw
        kkbeta = max(kkbeta, paw_data.iraug)
    end


    #
    # Dion matrix elements
    #
    Dion_temp = zeros(Nproj*Nproj)
    pp_dion = LightXML.get_elements_by_tagname(pp_nonlocal[1], "PP_DIJ")
    pp_dion_str = LightXML.content(pp_dion[1])
    pp_dion_str = replace(pp_dion_str, "\n" => " ")
    spl_str = split(pp_dion_str, keepempty=false)
    for i in 1:Nproj*Nproj
        Dion_temp[i] = parse(Float64,spl_str[i])
    end
    Dion = reshape(Dion_temp,(Nproj,Nproj))*0.5 #*2  # convert to Hartree

    # For compatibility with PsPot_GTH
    Nproj_l = zeros(Int64,4)
    for l in 0:lmax
        Nproj_l[l+1] = count(proj_l .== l)
    end
    #println("proj_l = ", proj_l)
    #println("Nproj_l = ", Nproj_l)

    # This is somewhat wasteful
    # Currently the 1st dimension of h is max number of supported angular
    # momentum, i.e. l=3 (or 4 in 1-based indexing)
    # 2nd and 3rd column should be number of projector per l. In GTH pspot
    # it is 3 at maximum
    nprjlmax = maximum(Nproj_l)
    h = zeros(Float64,4,nprjlmax,nprjlmax)
    istart = 0
    for l in 0:lmax
        idx = (istart+1):(istart+Nproj_l[l+1])
        istart = istart+Nproj_l[l+1]
        #display(Dion[idx,idx]); println()
        idx2 = 1:Nproj_l[l+1] 
        h[l+1,idx2,idx2] = Dion[idx,idx]
    end

    #
    # augmentation stuffs:
    #
    need_aug = is_ultrasoft || is_paw
    nqf, nqlc, qqq, q_with_l, qfuncl = 
    _read_us_aug(need_aug, pp_nonlocal, r, Nproj, proj_l, kkbeta, is_paw, paw_data)

    #
    # Pseudo wave function
    #
    pp_pswfc = LightXML.get_elements_by_tagname(xroot, "PP_PSWFC")
    Nchi = parse(Int64, LightXML.attributes_dict(pp_header[1])["number_of_wfc"])
    chi = zeros(Float64,Nr,Nchi)
    lchi = zeros(Int64,Nchi) # angular momentum (s: l=0, p: l=1, etc)
    occ_chi = zeros(Float64,Nchi)
    for iwf in 1:Nchi
        tagname = "PP_CHI."*string(iwf)
        pp_chi = LightXML.get_elements_by_tagname(pp_pswfc[1], tagname)
        #
        occ_chi[iwf] = parse(Float64, LightXML.attributes_dict(pp_chi[1])["occupation"])
        lchi[iwf] = parse(Float64, LightXML.attributes_dict(pp_chi[1])["l"])
        #
        pp_chi_str = LightXML.content(pp_chi[1])
        pp_chi_str = replace(pp_chi_str, "\n" => " ")
        spl_str = split(pp_chi_str, keepempty=false)
        for i in 1:Nr
            chi[i,iwf] = parse(Float64, spl_str[i])
        end
    end

    # rho atom
    rhoatom = zeros(Float64,Nr)
    pp_rhoatom = LightXML.get_elements_by_tagname(xroot, "PP_RHOATOM")
    pp_rhoatom_str = LightXML.content(pp_rhoatom[1])
    pp_rhoatom_str = replace(pp_rhoatom_str, "\n" => " ")
    spl_str = split(pp_rhoatom_str, keepempty=false)
    for i in 1:Nr
        rhoatom[i] = parse(Float64, spl_str[i])
    end

    LightXML.free(xdoc)


    return PsPot_UPF(upf_file, atsymb, zval,
        is_nlcc, is_ultrasoft, is_paw,
        Nr, r, rab, dx, xmin, rmax, zmesh,
        V_local, Nproj, proj_l, rcut_l, kkbeta, proj_func, Dion,
        h, lmax, Nproj_l,
        lmax_rho,
        rho_atc,
        nqf, nqlc, qqq, q_with_l, qfuncl,
        Nchi, chi, lchi, occ_chi,
        rhoatom,
        paw_data
    )

end


#
# Read data related to augmentation functions for USPP
#
function _read_us_aug(
    need_aug::Bool,
    pp_nonlocal,
    r::Array{Float64,1},
    Nproj::Int64,
    proj_l,
    kkbeta::Int64,
    is_paw,
    paw_data
)

    if !need_aug
        # Dummy data
        nqf = 0
        nqlc = 0
        qqq = zeros(1,1)
        q_with_l = false
        qfuncl = zeros(1,1,1)
        return nqf, nqlc, qqq, q_with_l, qfuncl
    end

    Nr = size(r,1)
    pp_aug = LightXML.get_elements_by_tagname(pp_nonlocal[1], "PP_AUGMENTATION")
    
    # number of angular momenta in Q
    nqlc = parse(Int64, LightXML.attributes_dict(pp_aug[1])["nqlc"])
    
    # From init_us_1.f90 in QE:
    #!
    #! the following prevents an out-of-bound error: upf(nt)%nqlc=2*lmax+1
    #! but in some versions of the PP files lmax is not set to the maximum
    #! l of the beta functions but includes the l of the local potential
    #!
    #do nt=1,ntyp
    #   upf(nt)%nqlc = MIN ( upf(nt)%nqlc, lmaxq )
    #   IF ( upf(nt)%nqlc < 0 )  upf(nt)%nqlc = 0
    #end do


    # number of Q coefficients
    nqf = parse(Int64, LightXML.attributes_dict(pp_aug[1])["nqf"])
    
    # XXX Also need to read q_with_l
    # For GBRV this is false
    str1 = LightXML.attributes_dict(pp_aug[1])["q_with_l"]
    if str1 == "F"
        q_with_l = false
    elseif str1 == "T"
        q_with_l = true
    else
        q_with_l = parse(Bool, str1)
    end

    pp_q = LightXML.get_elements_by_tagname(pp_aug[1], "PP_Q")
    pp_q_str = LightXML.content(pp_q[1])
    pp_q_str = replace(pp_q_str, "\n" => " ")
    spl_str = split(pp_q_str, keepempty=false)

    qqq = zeros(Nproj,Nproj)
    qqq_temp = zeros(Nproj*Nproj)
    for i in 1:Nproj*Nproj
        qqq_temp[i] = parse(Float64, spl_str[i])
    end
    qqq = reshape(qqq_temp, (Nproj,Nproj)) # XXX convert to Ha?

    if nqf > 0
        qfcoef_tmp = zeros(Float64, nqf*nqlc*Nproj*Nproj)
        pp_qfcoef = LightXML.get_elements_by_tagname(pp_aug[1], "PP_QFCOEF")
        pp_qfcoef_str = LightXML.content(pp_qfcoef[1])
        pp_qfcoef_str = replace(pp_qfcoef_str, "\n" => " ")
        spl_str = split(pp_qfcoef_str, keepempty=false)
        for i in 1:length(qfcoef_tmp)
            qfcoef_tmp[i] = parse(Float64, spl_str[i])
        end
        qfcoef = reshape(qfcoef_tmp, nqf, nqlc, Nproj, Nproj)
        #
        pp_rinner = LightXML.get_elements_by_tagname(pp_aug[1], "PP_RINNER")
        pp_rinner_str = LightXML.content(pp_rinner[1])
        pp_rinner_str = replace(pp_rinner_str, "\n" => " ")
        spl_str = split(pp_rinner_str, keepempty=false)
        rinner = zeros(Float64, nqlc)
        for i in 1:nqlc
            rinner[i] = parse(Float64, spl_str[i])
        end
    end


    Nq = Int64( Nproj*(Nproj+1)/2 )
    qfunc = zeros(Float64, Nr, Nq)
    qfuncl = zeros(Float64,Nr,Nq,nqlc) # last index is l
    QFUNC2Ha = 1.0

    if !q_with_l
        for iprj in 1:Nproj, jprj in iprj:Nproj
            tagname = "PP_QIJ."*string(iprj)*"."*string(jprj)
            pp_qij = LightXML.get_elements_by_tagname(pp_aug[1], tagname)
            #
            first_idx = parse( Int64, LightXML.attributes_dict(pp_qij[1])["first_index"] )
            second_idx = parse( Int64, LightXML.attributes_dict(pp_qij[1])["second_index"] )
            comp_idx = parse( Int64, LightXML.attributes_dict(pp_qij[1])["composite_index"] )
            #
            pp_qij_str = LightXML.content(pp_qij[1])
            pp_qij_str = replace(pp_qij_str, "\n" => " ")
            spl_str = split(pp_qij_str, keepempty=false)
            # FIXME: using comp_idx?
            # FIXME: Need to check the unit of qfunc, need to convert to Ha?
            for i in 1:Nr
                qfunc[i,comp_idx] = parse(Float64,spl_str[i])*QFUNC2Ha
            end
        end

        # Prepare qfuncl
        for nb in 1:Nproj, mb in nb:Nproj
            # ijv is the combined (nb,mb) index
            ijv = round(Int64, mb*(mb-1)/2) + nb
            l1 = proj_l[nb]
            l2 = proj_l[mb]
            # copy q(r) to the l-dependent grid 
            for l in range( abs(l1-l2), stop=(l1+l2), step=2)
                #@printf("nb, mb, l = %d %d %d\n", nb, mb, l)
                @views qfuncl[1:Nr,ijv,l+1] = qfunc[1:Nr,ijv] # index l starts from 1
            end
            #
            if nqf > 0
                for l in range(abs(l1-l2), stop=l1+l2, step=2)
                    if rinner[l+1] > 0.0
                        ilast = 0
                        for ir in 1:kkbeta
                            if r[ir] < rinner[l+1]
                                ilast = ir
                            end
                        end
                        @views _setqfnew!( nqf, qfcoef[:,l+1,nb,mb], ilast, r, l, 2, qfuncl[:,ijv,l+1] )
                    end # if
                end # for
            end # if
        end
    else
        # Read QIJL
        # TODO: Check for augmom in paw_data
        # TODO: Ref: read_upf_new
        for nb in 1:Nproj, mb in nb:Nproj
            ijv = round(Int64, mb*(mb-1)/2) + nb
            l1 = proj_l[nb]
            l2 = proj_l[mb]
            for l in range( abs(l1-l2), stop=(l1+l2), step=2)

                is_null = false 
                if is_paw
                    is_null = abs(paw_data.augmom[nb,mb,l+1]) < paw_data.qqq_eps
                end
                #println("is_null = ", is_null)
                # Note that augmom is originally indexed from 0
                if is_null
                    println("Skip l = ", l)
                    continue
                end

                tagname = "PP_QIJL."*string(nb)*"."*string(mb)*"."*string(l)
                pp_qijl = LightXML.get_elements_by_tagname(pp_aug[1], tagname)
                #
                first_idx = parse( Int64, LightXML.attributes_dict(pp_qijl[1])["first_index"] )
                second_idx = parse( Int64, LightXML.attributes_dict(pp_qijl[1])["second_index"] )
                comp_idx = parse( Int64, LightXML.attributes_dict(pp_qijl[1])["composite_index"] )
                am_idx = parse( Int64, LightXML.attributes_dict(pp_qijl[1])["angular_momentum"] )
                #println("l, comp_idx = ", l, " ", comp_idx)
                if ijv != comp_idx
                    println("WARNING: ijv != comp_idx")
                end
                if am_idx != l
                    println("WARNING: am_idx != l")
                end
                #
                str1 = LightXML.content(pp_qijl[1])
                str1 = replace(str1, "\n" => " ")
                spl_str = split(str1, keepempty=false)
                # FIXME: using comp_idx?
                # FIXME: convert to Ha?
                for i in 1:Nr
                    qfuncl[i,comp_idx,l+1] = parse(Float64,spl_str[i])*QFUNC2Ha
                end
                if is_paw
                    qfuncl[paw_data.iraug+1:end,comp_idx,l+1] .= 0.0
                end
            end
        end
    end

    return nqf, nqlc, qqq, q_with_l, qfuncl
end


#
# Adapted from QE:
# subroutine setqfnew in upflib/upf_to_internal
#
function _setqfnew!(nqf, qfcoef, Nr, r, l, n, rho)
    #
    # FIXME: n is always equal to 2 ?
    #
    # Computes the Q function from its polynomial expansion (r < rinner)
    # On input: nqf = number of polynomial coefficients
    #    qfcoef(1:nqf) = the coefficients defining Q
    #          Nr = number of mesh point
    #        r(1:Nr)= the radial mesh
    #             l = angular momentum
    #             n = additional exponent, result is multiplied by r^n
    # On output:
    #      rho(1:Nr)= r^n * Q(r)
    for ir in 1:Nr
        rr = r[ir]^2
        rho[ir] = qfcoef[1]
        for i in 2:nqf
           rho[ir] = rho[ir] + qfcoef[i] * rr^(i-1)
        end
        rho[ir] = rho[ir]*r[ir]^(l + n)
    end
    return
end


# From uspp.f90 n_atom_wfc function
# Copyright (C) 2004-2011 Quantum ESPRESSO group
function calc_Natomwfc( atoms::Atoms, pspots::Vector{PsPot_UPF} )
    Natoms = atoms.Natoms
    atm2species = atoms.atm2species
    # Find number of starting atomic orbitals    
    Natomwfc = 0
    for ia in 1:Natoms
        isp = atm2species[ia]
        psp = pspots[isp]
        # We use Nchi here
        # Nwfc is reserved for wfcs for projectors (beta function)
        for i in 1:psp.Nchi
            if psp.occ_chi[i] >= 0.0
                Natomwfc += 2*psp.lchi[i] + 1
            end
        end
    end
    return Natomwfc
end



# This routine computes the Fourier transform of the local
# part of an atomic pseudopotential, given in numerical form.
# A term erf(r)/r is subtracted in real space (thus making the
# function short-ranged) and added again in G space (for G != 0)
# The G=0 term contains \int (V_loc(r)+ Ze^2/r) 4pi r^2 dr.
# This is the "alpha" in the so-called "alpha Z" term of the energy.
#
# Adapted from the file vloc_of_g.f90
#
# Copyright (C) 2001-2007 Quantum ESPRESSO group
# 
function eval_Vloc_G!(
    psp::PsPot_UPF,
    G2_shells::Vector{Float64},
    Vloc_G::AbstractVector{Float64}
)

    r = psp.r
    Nr_full = psp.Nr
    Nr = Nr_full

    RCUT = 10.0
    for i in 1:Nr_full
        if r[i] > RCUT
            Nr = i
            break
        end 
    end
    # Force Nr to be odd number
    Nr = 2*floor(Int64, (Nr + 1)/2) - 1
    #println("Nr = ", Nr)

    rab = psp.rab
    Vloc_at = psp.V_local
    zval = psp.zval
    Ngl = length(G2_shells)

    fill!(Vloc_G, 0.0)
    aux = zeros(Float64, Nr)
    aux1 = zeros(Float64, Nr)

    if G2_shells[1] < 1e-8
        # first the G=0 term
        for ir in 1:Nr
            aux[ir] = r[ir] * ( r[ir] * Vloc_at[ir] + zval )
        end
        Vloc_G[1] = 4π*integ_simpson(Nr, aux, rab)
        igl0 = 2
    else
        igl0 = 1
    end

    # here the G != 0 terms, we first compute the part of the integrand 
    # function independent of |G| in real space
    for ir in 1:Nr
       aux1[ir] = r[ir] * Vloc_at[ir] + zval * erf(r[ir])
    end

    for igl in igl0:Ngl
        Gx = sqrt( G2_shells[igl] )
        for ir in 1:Nr
            aux[ir] = aux1[ir] * sin(Gx*r[ir])/Gx
        end
        Vgl = integ_simpson( Nr, aux, rab )
        Vloc_G[igl] = 4π*(Vgl - zval * exp(-0.25*G2_shells[igl])/G2_shells[igl])
    end
    return
end



#=
function eval_proj_G(psp::PsPot_UPF, iprjl::Int64, Gm::Float64)
    #
    dq = 0.01 # HARDCODED
    tab = psp.prj_interp_table
    #
    # Interpolation procedure
    px = Gm/dq - floor(Int64, Gm/dq)
    ux = 1.0 - px
    vx = 2.0 - px
    wx = 3.0 - px
    i0 = floor(Int64, Gm/dq) + 1
    i1 = i0 + 1
    i2 = i0 + 2
    i3 = i0 + 3
    Vq = tab[i0,iprjl] * ux * vx * wx / 6.0 +
         tab[i1,iprjl] * px * vx * wx / 2.0 -
         tab[i2,iprjl] * px * ux * wx / 2.0 +
         tab[i3,iprjl] * px * ux * vx / 6.0
    return Vq
end
=#

import Base: show
function show( io::IO, psp::PsPot_UPF; header=true )
    println("\nUPF Info")
    @printf(io, "File = %s\n", psp.pspfile)
    @printf(io, "zval = %f\n", psp.zval)
    println(io, "is_nlcc = ", psp.is_nlcc)
end
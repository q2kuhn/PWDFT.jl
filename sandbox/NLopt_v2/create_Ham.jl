function create_Ham_Pt_fcc_smearing()
    atoms = Atoms(xyz_string_frac=
        """
        1

        Pt  0.0  0.0  0.0
        """, LatVecs=gen_lattice_fcc(3.9231*ANG2BOHR))
    pspfiles = [joinpath(DIR_PSP, "Pt-q10.gth")]
    ecutwfc = 30.0
    return Hamiltonian( atoms, pspfiles, ecutwfc,
                       meshk=[3,3,3], extra_states=4 )
end

function create_Ham_atom_Pt_smearing()
    atoms = Atoms(xyz_string_frac=
        """
        1

        Pt  0.0  0.0  0.0
        """, LatVecs=gen_lattice_sc(16.0))
    pspfiles = [joinpath(DIR_PSP, "Pt-q10.gth")]
    ecutwfc = 30.0
    return Hamiltonian( atoms, pspfiles, ecutwfc, extra_states=4 )
end

# without extra_states
function create_Ham_atom_Pt()
    atoms = Atoms(xyz_string_frac=
        """
        1

        Pt  0.0  0.0  0.0
        """, LatVecs=gen_lattice_sc(16.0))
    pspfiles = [joinpath(DIR_PSP, "Pt-q10.gth")]
    ecutwfc = 30.0
    return Hamiltonian( atoms, pspfiles, ecutwfc )
end

function create_Ham_atom_Al_smearing()
    atoms = Atoms(xyz_string_frac=
        """
        1

        Al  0.0  0.0  0.0
        """, LatVecs=gen_lattice_sc(16.0))
    pspfiles = [joinpath(DIR_PSP, "Al-q3.gth")]
    ecutwfc = 15.0
    return Hamiltonian( atoms, pspfiles, ecutwfc, extra_states=4 )
end

function create_Ham_Al_fcc_smearing()
    atoms = Atoms( xyz_string_frac=
        """
        1

        Al  0.0  0.0  0.0
        """, in_bohr=true,
        LatVecs = gen_lattice_fcc(7.6525970200) )
    pspfiles = [joinpath(DIR_PSP, "Al-q3.gth")]
    ecutwfc = 15.0
    return Hamiltonian( atoms, pspfiles, ecutwfc,
                       meshk=[3,3,3], extra_states=4 )

end
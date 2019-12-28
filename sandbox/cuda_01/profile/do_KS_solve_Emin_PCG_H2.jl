using Printf

using CUDAdrv
using CuArrays
using PWDFT
using PWDFT_cuda

const DIR_PWDFT = joinpath(dirname(pathof(PWDFT)),"..")
const DIR_PSP = joinpath(DIR_PWDFT, "pseudopotentials", "pade_gth")
const DIR_STRUCTURES = joinpath(DIR_PWDFT, "structures")

function main_GPU()

    CuArrays.seed!(1234)

    atoms = Atoms( xyz_file=joinpath(DIR_STRUCTURES, "H2.xyz"),
                   LatVecs=gen_lattice_sc(16.0) )
    pspfiles = [ joinpath(DIR_PSP, "H-q1.gth") ]
    ecutwfc = 15.0

    Nspin = 1

    Ham = CuHamiltonian( atoms, pspfiles, ecutwfc, use_symmetry=false, Nspin=Nspin )
    KS_solve_Emin_PCG!( Ham, skip_initial_diag=true, startingrhoe=:random )

end

main_GPU()
#CUDAdrv.@profile main_GPU()
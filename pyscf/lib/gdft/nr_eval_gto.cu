/*
 * gpu4pyscf is a plugin to use Nvidia GPU in PySCF package
 *
 * Copyright (C) 2022 Qiming Sun
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <http://www.gnu.org/licenses/>.
 */

#include <stdio.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <assert.h>
#include <cuda_runtime.h>
#include <cint.h>
#include "gint/cuda_alloc.cuh"
#include "nr_eval_gto.cuh"
#include "contract_rho.cuh"

#define THREADS         128

template <int ANG> __global__
static void _cart_kernel_deriv0(BasOffsets offsets)
{
    int ngrids = offsets.ngrids;
    int grid_id = blockIdx.x * blockDim.x + threadIdx.x;
    if (grid_id >= ngrids) {
        return;
    }

    int bas_id = blockIdx.y;
    int natm = c_envs.natm;
    int ish = offsets.bas_off + bas_id;
    int atm_id = c_bas_atom[ish];
    size_t i0 = c_envs.ao_loc[ish];
    double* __restrict__ gto = offsets.data + i0 * ngrids;

    //if (c_envs.mask[blockIdx.x + blockIdx.y * c_envs.nbas] == 0) {
    //    int i1 = c_envs.ao_loc[ish+1];
    //    int nf = i1 - i0;
    //    for (int i = 0; i < nf; ++i) {
    //        gto[i*ngrids+grid_id] = 0;
    //    }
    //    return;
    //}

    double *atom_coordx = c_envs.atom_coordx;
    double *atom_coordy = c_envs.atom_coordx + natm;
    double *atom_coordz = c_envs.atom_coordx + natm * 2;
    double *gridx = offsets.gridx;
    double *gridy = offsets.gridx + ngrids;
    double *gridz = offsets.gridx + ngrids * 2;
    double rx = gridx[grid_id] - atom_coordx[atm_id];
    double ry = gridy[grid_id] - atom_coordy[atm_id];
    double rz = gridz[grid_id] - atom_coordz[atm_id];
    double rr = rx * rx + ry * ry + rz * rz;
    double *exps = c_envs.env + c_bas_exp[ish];
    double *coeffs = c_envs.env + c_bas_coeff[ish];

    double ce = 0;
    for (int ip = 0; ip < offsets.nprim; ++ip) {
        ce += coeffs[ip] * exp(-exps[ip] * rr);
    }
    ce *= offsets.fac;

    if (ANG == 0) {
        gto[grid_id] = ce;
    } else if (ANG == 1) {
        gto[         grid_id] = ce * rx;
        gto[1*ngrids+grid_id] = ce * ry;
        gto[2*ngrids+grid_id] = ce * rz;
    } else if (ANG == 2) {
        gto[         grid_id] = ce * rx * rx;
        gto[1*ngrids+grid_id] = ce * rx * ry;
        gto[2*ngrids+grid_id] = ce * rx * rz;
        gto[3*ngrids+grid_id] = ce * ry * ry;
        gto[4*ngrids+grid_id] = ce * ry * rz;
        gto[5*ngrids+grid_id] = ce * rz * rz;
    } else if (ANG == 3) {
        gto[         grid_id] = ce * rx * rx * rx;
        gto[1*ngrids+grid_id] = ce * rx * rx * ry;
        gto[2*ngrids+grid_id] = ce * rx * rx * rz;
        gto[3*ngrids+grid_id] = ce * rx * ry * ry;
        gto[4*ngrids+grid_id] = ce * rx * ry * rz;
        gto[5*ngrids+grid_id] = ce * rx * rz * rz;
        gto[6*ngrids+grid_id] = ce * ry * ry * ry;
        gto[7*ngrids+grid_id] = ce * ry * ry * rz;
        gto[8*ngrids+grid_id] = ce * ry * rz * rz;
        gto[9*ngrids+grid_id] = ce * rz * rz * rz;
    } else if (ANG == 4) {
        gto[          grid_id] = ce * rx * rx * rx * rx;
        gto[1 *ngrids+grid_id] = ce * rx * rx * rx * ry;
        gto[2 *ngrids+grid_id] = ce * rx * rx * rx * rz;
        gto[3 *ngrids+grid_id] = ce * rx * rx * ry * ry;
        gto[4 *ngrids+grid_id] = ce * rx * rx * ry * rz;
        gto[5 *ngrids+grid_id] = ce * rx * rx * rz * rz;
        gto[6 *ngrids+grid_id] = ce * rx * ry * ry * ry;
        gto[7 *ngrids+grid_id] = ce * rx * ry * ry * rz;
        gto[8 *ngrids+grid_id] = ce * rx * ry * rz * rz;
        gto[9 *ngrids+grid_id] = ce * rx * rz * rz * rz;
        gto[10*ngrids+grid_id] = ce * ry * ry * ry * ry;
        gto[11*ngrids+grid_id] = ce * ry * ry * ry * rz;
        gto[12*ngrids+grid_id] = ce * ry * ry * rz * rz;
        gto[13*ngrids+grid_id] = ce * ry * rz * rz * rz;
        gto[14*ngrids+grid_id] = ce * rz * rz * rz * rz;
    }
}


template <int ANG> __global__
static void _cart_kernel_deriv1(BasOffsets offsets)
{
    int ngrids = offsets.ngrids;
    int grid_id = blockIdx.x * blockDim.x + threadIdx.x;
    if (grid_id >= ngrids) {
        return;
    }

    int bas_id = blockIdx.y;
    int natm = c_envs.natm;
    int nbas = c_envs.nbas;
    int nao = c_envs.ao_loc[nbas];
    int ish = offsets.bas_off + bas_id;
    int atm_id = c_bas_atom[ish];
    size_t i0 = c_envs.ao_loc[ish];
    double* __restrict__ gto = offsets.data + i0 * ngrids;
    double* __restrict__ gtox = offsets.data + (nao * 1 + i0) * ngrids;
    double* __restrict__ gtoy = offsets.data + (nao * 2 + i0) * ngrids;
    double* __restrict__ gtoz = offsets.data + (nao * 3 + i0) * ngrids;

    double *atom_coordx = c_envs.atom_coordx;
    double *atom_coordy = c_envs.atom_coordx + natm;
    double *atom_coordz = c_envs.atom_coordx + natm * 2;
    double *gridx = offsets.gridx;
    double *gridy = offsets.gridx + ngrids;
    double *gridz = offsets.gridx + ngrids * 2;
    double rx = gridx[grid_id] - atom_coordx[atm_id];
    double ry = gridy[grid_id] - atom_coordy[atm_id];
    double rz = gridz[grid_id] - atom_coordz[atm_id];
    double rr = rx * rx + ry * ry + rz * rz;
    double *exps = c_envs.env + c_bas_exp[ish];
    double *coeffs = c_envs.env + c_bas_coeff[ish];

    double ce = 0;
    double ce_2a = 0;
    for (int ip = 0; ip < offsets.nprim; ++ip) {
        double c = coeffs[ip];
        double e = exp(-exps[ip] * rr);
        ce += c * e;
        ce_2a += c * e * exps[ip];
    }
    ce *= offsets.fac;
    ce_2a *= -2 * offsets.fac;

    if (ANG == 0) {
        gto [grid_id] = ce;
        gtox[grid_id] = ce_2a * rx;
        gtoy[grid_id] = ce_2a * ry;
        gtoz[grid_id] = ce_2a * rz;
    } else if (ANG == 1) {
        double ax = ce_2a * rx;
        double ay = ce_2a * ry;
        double az = ce_2a * rz;
        gto [         grid_id] = ce * rx;
        gto [1*ngrids+grid_id] = ce * ry;
        gto [2*ngrids+grid_id] = ce * rz;
        gtox[         grid_id] = ax * rx + ce;
        gtox[1*ngrids+grid_id] = ax * ry;
        gtox[2*ngrids+grid_id] = ax * rz;
        gtoy[         grid_id] = ay * rx;
        gtoy[1*ngrids+grid_id] = ay * ry + ce;
        gtoy[2*ngrids+grid_id] = ay * rz;
        gtoz[         grid_id] = az * rx;
        gtoz[1*ngrids+grid_id] = az * ry;
        gtoz[2*ngrids+grid_id] = az * rz + ce;
    } else if (ANG == 2) {
        double ax = ce_2a * rx;
        double ay = ce_2a * ry;
        double az = ce_2a * rz;
        double bx = ce * rx;
        double by = ce * ry;
        double bz = ce * rz;
        gto [         grid_id] = ce * rx * rx;
        gto [1*ngrids+grid_id] = ce * rx * ry;
        gto [2*ngrids+grid_id] = ce * rx * rz;
        gto [3*ngrids+grid_id] = ce * ry * ry;
        gto [4*ngrids+grid_id] = ce * ry * rz;
        gto [5*ngrids+grid_id] = ce * rz * rz;
        gtox[         grid_id] = ax * rx * rx + 2 * bx;
        gtox[1*ngrids+grid_id] = ax * rx * ry +     by;
        gtox[2*ngrids+grid_id] = ax * rx * rz +     bz;
        gtox[3*ngrids+grid_id] = ax * ry * ry;
        gtox[4*ngrids+grid_id] = ax * ry * rz;
        gtox[5*ngrids+grid_id] = ax * rz * rz;
        gtoy[         grid_id] = ay * rx * rx;
        gtoy[1*ngrids+grid_id] = ay * rx * ry +     bx;
        gtoy[2*ngrids+grid_id] = ay * rx * rz;
        gtoy[3*ngrids+grid_id] = ay * ry * ry + 2 * by;
        gtoy[4*ngrids+grid_id] = ay * ry * rz +     bz;
        gtoy[5*ngrids+grid_id] = ay * rz * rz;
        gtoz[         grid_id] = az * rx * rx;
        gtoz[1*ngrids+grid_id] = az * rx * ry;
        gtoz[2*ngrids+grid_id] = az * rx * rz +     bx;
        gtoz[3*ngrids+grid_id] = az * ry * ry;
        gtoz[4*ngrids+grid_id] = az * ry * rz +     by;
        gtoz[5*ngrids+grid_id] = az * rz * rz + 2 * bz;
    } else if (ANG == 3) {
        double ax = ce_2a * rx;
        double ay = ce_2a * ry;
        double az = ce_2a * rz;
        double bxx = ce * rx * rx;
        double bxy = ce * rx * ry;
        double bxz = ce * rx * rz;
        double byy = ce * ry * ry;
        double byz = ce * ry * rz;
        double bzz = ce * rz * rz;
        gto [         grid_id] = ce * rx * rx * rx;
        gto [1*ngrids+grid_id] = ce * rx * rx * ry;
        gto [2*ngrids+grid_id] = ce * rx * rx * rz;
        gto [3*ngrids+grid_id] = ce * rx * ry * ry;
        gto [4*ngrids+grid_id] = ce * rx * ry * rz;
        gto [5*ngrids+grid_id] = ce * rx * rz * rz;
        gto [6*ngrids+grid_id] = ce * ry * ry * ry;
        gto [7*ngrids+grid_id] = ce * ry * ry * rz;
        gto [8*ngrids+grid_id] = ce * ry * rz * rz;
        gto [9*ngrids+grid_id] = ce * rz * rz * rz;
        gtox[         grid_id] = ax * rx * rx * rx + 3 * bxx;
        gtox[1*ngrids+grid_id] = ax * rx * rx * ry + 2 * bxy;
        gtox[2*ngrids+grid_id] = ax * rx * rx * rz + 2 * bxz;
        gtox[3*ngrids+grid_id] = ax * rx * ry * ry +     byy;
        gtox[4*ngrids+grid_id] = ax * rx * ry * rz +     byz;
        gtox[5*ngrids+grid_id] = ax * rx * rz * rz +     bzz;
        gtox[6*ngrids+grid_id] = ax * ry * ry * ry;
        gtox[7*ngrids+grid_id] = ax * ry * ry * rz;
        gtox[8*ngrids+grid_id] = ax * ry * rz * rz;
        gtox[9*ngrids+grid_id] = ax * rz * rz * rz;
        gtoy[         grid_id] = ay * rx * rx * rx;
        gtoy[1*ngrids+grid_id] = ay * rx * rx * ry +     bxx;
        gtoy[2*ngrids+grid_id] = ay * rx * rx * rz;
        gtoy[3*ngrids+grid_id] = ay * rx * ry * ry + 2 * bxy;
        gtoy[4*ngrids+grid_id] = ay * rx * ry * rz +     bxz;
        gtoy[5*ngrids+grid_id] = ay * rx * rz * rz;
        gtoy[6*ngrids+grid_id] = ay * ry * ry * ry + 3 * byy;
        gtoy[7*ngrids+grid_id] = ay * ry * ry * rz + 2 * byz;
        gtoy[8*ngrids+grid_id] = ay * ry * rz * rz +     bzz;
        gtoy[9*ngrids+grid_id] = ay * rz * rz * rz;
        gtoz[         grid_id] = az * rx * rx * rx;
        gtoz[1*ngrids+grid_id] = az * rx * rx * ry;
        gtoz[2*ngrids+grid_id] = az * rx * rx * rz +     bxx;
        gtoz[3*ngrids+grid_id] = az * rx * ry * ry;
        gtoz[4*ngrids+grid_id] = az * rx * ry * rz +     bxy;
        gtoz[5*ngrids+grid_id] = az * rx * rz * rz + 2 * bxz;
        gtoz[6*ngrids+grid_id] = az * ry * ry * ry;
        gtoz[7*ngrids+grid_id] = az * ry * ry * rz +     byy;
        gtoz[8*ngrids+grid_id] = az * ry * rz * rz + 2 * byz;
        gtoz[9*ngrids+grid_id] = az * rz * rz * rz + 3 * bzz;
    } else if (ANG == 4) {
        double ax = ce_2a * rx;
        double ay = ce_2a * ry;
        double az = ce_2a * rz;
        double bxxx = ce * rx * rx * rx;
        double bxxy = ce * rx * rx * ry;
        double bxxz = ce * rx * rx * rz;
        double bxyy = ce * rx * ry * ry;
        double bxyz = ce * rx * ry * rz;
        double bxzz = ce * rx * rz * rz;
        double byyy = ce * ry * ry * ry;
        double byyz = ce * ry * ry * rz;
        double byzz = ce * ry * rz * rz;
        double bzzz = ce * rz * rz * rz;
        gto [          grid_id] = ce * rx * rx * rx * rx;
        gto [1 *ngrids+grid_id] = ce * rx * rx * rx * ry;
        gto [2 *ngrids+grid_id] = ce * rx * rx * rx * rz;
        gto [3 *ngrids+grid_id] = ce * rx * rx * ry * ry;
        gto [4 *ngrids+grid_id] = ce * rx * rx * ry * rz;
        gto [5 *ngrids+grid_id] = ce * rx * rx * rz * rz;
        gto [6 *ngrids+grid_id] = ce * rx * ry * ry * ry;
        gto [7 *ngrids+grid_id] = ce * rx * ry * ry * rz;
        gto [8 *ngrids+grid_id] = ce * rx * ry * rz * rz;
        gto [9 *ngrids+grid_id] = ce * rx * rz * rz * rz;
        gto [10*ngrids+grid_id] = ce * ry * ry * ry * ry;
        gto [11*ngrids+grid_id] = ce * ry * ry * ry * rz;
        gto [12*ngrids+grid_id] = ce * ry * ry * rz * rz;
        gto [13*ngrids+grid_id] = ce * ry * rz * rz * rz;
        gto [14*ngrids+grid_id] = ce * rz * rz * rz * rz;
        gtox[          grid_id] = ax * rx * rx * rx * rx + 4 * bxxx;
        gtox[1 *ngrids+grid_id] = ax * rx * rx * rx * ry + 3 * bxxy;
        gtox[2 *ngrids+grid_id] = ax * rx * rx * rx * rz + 3 * bxxz;
        gtox[3 *ngrids+grid_id] = ax * rx * rx * ry * ry + 2 * bxyy;
        gtox[4 *ngrids+grid_id] = ax * rx * rx * ry * rz + 2 * bxyz;
        gtox[5 *ngrids+grid_id] = ax * rx * rx * rz * rz + 2 * bxzz;
        gtox[6 *ngrids+grid_id] = ax * rx * ry * ry * ry +     byzz;
        gtox[7 *ngrids+grid_id] = ax * rx * ry * ry * rz +     byzz;
        gtox[8 *ngrids+grid_id] = ax * rx * ry * rz * rz +     byzz;
        gtox[9 *ngrids+grid_id] = ax * rx * rz * rz * rz +     bzzz;
        gtox[10*ngrids+grid_id] = ax * ry * ry * ry * ry;
        gtox[11*ngrids+grid_id] = ax * ry * ry * ry * rz;
        gtox[12*ngrids+grid_id] = ax * ry * ry * rz * rz;
        gtox[13*ngrids+grid_id] = ax * ry * rz * rz * rz;
        gtox[14*ngrids+grid_id] = ax * rz * rz * rz * rz;
        gtoy[          grid_id] = ay * rx * rx * rx * rx;          
        gtoy[1 *ngrids+grid_id] = ay * rx * rx * rx * ry +     bxxx;
        gtoy[2 *ngrids+grid_id] = ay * rx * rx * rx * rz;
        gtoy[3 *ngrids+grid_id] = ay * rx * rx * ry * ry + 2 * bxxy;
        gtoy[4 *ngrids+grid_id] = ay * rx * rx * ry * rz +     bxxz;
        gtoy[5 *ngrids+grid_id] = ay * rx * rx * rz * rz;
        gtoy[6 *ngrids+grid_id] = ay * rx * ry * ry * ry + 3 * bxyy;
        gtoy[7 *ngrids+grid_id] = ay * rx * ry * ry * rz + 2 * bxyz;
        gtoy[8 *ngrids+grid_id] = ay * rx * ry * rz * rz +     bxzz;
        gtoy[9 *ngrids+grid_id] = ay * rx * rz * rz * rz;
        gtoy[10*ngrids+grid_id] = ay * ry * ry * ry * ry + 4 * byyy;
        gtoy[11*ngrids+grid_id] = ay * ry * ry * ry * rz + 3 * byyz;
        gtoy[12*ngrids+grid_id] = ay * ry * ry * rz * rz + 2 * byzz;
        gtoy[13*ngrids+grid_id] = ay * ry * rz * rz * rz +     bzzz;
        gtoy[14*ngrids+grid_id] = ay * rz * rz * rz * rz;          
        gtoz[          grid_id] = az * rx * rx * rx * rx;
        gtoz[1 *ngrids+grid_id] = az * rx * rx * rx * ry;
        gtoz[2 *ngrids+grid_id] = az * rx * rx * rx * rz +     bxxx;
        gtoz[3 *ngrids+grid_id] = az * rx * rx * ry * ry; 
        gtoz[4 *ngrids+grid_id] = az * rx * rx * ry * rz +     bxxy;
        gtoz[5 *ngrids+grid_id] = az * rx * rx * rz * rz + 2 * bxxz;
        gtoz[6 *ngrids+grid_id] = az * rx * ry * ry * ry;
        gtoz[7 *ngrids+grid_id] = az * rx * ry * ry * rz +     bxyy;
        gtoz[8 *ngrids+grid_id] = az * rx * ry * rz * rz + 2 * bxyz;
        gtoz[9 *ngrids+grid_id] = az * rx * rz * rz * rz + 3 * bxzz;
        gtoz[10*ngrids+grid_id] = az * ry * ry * ry * ry;
        gtoz[11*ngrids+grid_id] = az * ry * ry * ry * rz +     byyy;
        gtoz[12*ngrids+grid_id] = az * ry * ry * rz * rz + 2 * byyz;
        gtoz[13*ngrids+grid_id] = az * ry * rz * rz * rz + 3 * byzz;
        gtoz[14*ngrids+grid_id] = az * rz * rz * rz * rz + 4 * bzzz;
    }
}

template <int ANG> __global__
static void _sph_kernel_deriv0(BasOffsets offsets)
{
    int ngrids = offsets.ngrids;
    int grid_id = blockIdx.x * blockDim.x + threadIdx.x;
    if (grid_id >= ngrids) {
        return;
    }

    int bas_id = blockIdx.y;
    int natm = c_envs.natm;
    int ish = offsets.bas_off + bas_id;
    int atm_id = c_bas_atom[ish];
    size_t i0 = c_envs.ao_loc[ish];
    double* __restrict__ gto = offsets.data + i0 * ngrids;

    double *atom_coordx = c_envs.atom_coordx;
    double *atom_coordy = c_envs.atom_coordx + natm;
    double *atom_coordz = c_envs.atom_coordx + natm * 2;
    double *gridx = offsets.gridx;
    double *gridy = offsets.gridx + ngrids;
    double *gridz = offsets.gridx + ngrids * 2;
    double rx = gridx[grid_id] - atom_coordx[atm_id];
    double ry = gridy[grid_id] - atom_coordy[atm_id];
    double rz = gridz[grid_id] - atom_coordz[atm_id];
    double rr = rx * rx + ry * ry + rz * rz;
    double *exps = c_envs.env + c_bas_exp[ish];
    double *coeffs = c_envs.env + c_bas_coeff[ish];

    double ce = 0;
    for (int ip = 0; ip < offsets.nprim; ++ip) {
        ce += coeffs[ip] * exp(-exps[ip] * rr);
    }
    ce *= offsets.fac;

    if (ANG == 2) {
        double g0 = ce * rx * rx;
        double g1 = ce * rx * ry;
        double g2 = ce * rx * rz;
        double g3 = ce * ry * ry;
        double g4 = ce * ry * rz;
        double g5 = ce * rz * rz;
        gto[         grid_id] = 1.092548430592079070 * g1;
        gto[1*ngrids+grid_id] = 1.092548430592079070 * g4;
        gto[2*ngrids+grid_id] = 0.630783130505040012 * g5 - 0.315391565252520002 * g0 - 0.315391565252520002 * g3;
        gto[3*ngrids+grid_id] = 1.092548430592079070 * g2;
        gto[4*ngrids+grid_id] = 0.546274215296039535 * g0 - 0.546274215296039535 * g3;
    } else if (ANG == 3) {
        double g0 = ce * rx * rx * rx;
        double g1 = ce * rx * rx * ry;
        double g2 = ce * rx * rx * rz;
        double g3 = ce * rx * ry * ry;
        double g4 = ce * rx * ry * rz;
        double g5 = ce * rx * rz * rz;
        double g6 = ce * ry * ry * ry;
        double g7 = ce * ry * ry * rz;
        double g8 = ce * ry * rz * rz;
        double g9 = ce * rz * rz * rz;
        gto[         grid_id] = 1.770130769779930531 * g1 - 0.590043589926643510 * g6;
        gto[1*ngrids+grid_id] = 2.890611442640554055 * g4;
        gto[2*ngrids+grid_id] = 1.828183197857862944 * g8 - 0.457045799464465739 * g1 - 0.457045799464465739 * g6;
        gto[3*ngrids+grid_id] = 0.746352665180230782 * g9 - 1.119528997770346170 * g2 - 1.119528997770346170 * g7;
        gto[4*ngrids+grid_id] = 1.828183197857862944 * g5 - 0.457045799464465739 * g0 - 0.457045799464465739 * g3;
        gto[5*ngrids+grid_id] = 1.445305721320277020 * g2 - 1.445305721320277020 * g7;
        gto[6*ngrids+grid_id] = 0.590043589926643510 * g0 - 1.770130769779930530 * g3;
    } else if (ANG == 4) {
        double g0  = ce * rx * rx * rx * rx;
        double g1  = ce * rx * rx * rx * ry;
        double g2  = ce * rx * rx * rx * rz;
        double g3  = ce * rx * rx * ry * ry;
        double g4  = ce * rx * rx * ry * rz;
        double g5  = ce * rx * rx * rz * rz;
        double g6  = ce * rx * ry * ry * ry;
        double g7  = ce * rx * ry * ry * rz;
        double g8  = ce * rx * ry * rz * rz;
        double g9  = ce * rx * rz * rz * rz;
        double g10 = ce * ry * ry * ry * ry;
        double g11 = ce * ry * ry * ry * rz;
        double g12 = ce * ry * ry * rz * rz;
        double g13 = ce * ry * rz * rz * rz;
        double g14 = ce * rz * rz * rz * rz;
        gto[         grid_id] = 2.503342941796704538 * g1 - 2.503342941796704530 * g6 ;
        gto[1*ngrids+grid_id] = 5.310392309339791593 * g4 - 1.770130769779930530 * g11;
        gto[2*ngrids+grid_id] = 5.677048174545360108 * g8 - 0.946174695757560014 * g1 - 0.946174695757560014 * g6 ;
        gto[3*ngrids+grid_id] = 2.676186174229156671 * g13- 2.007139630671867500 * g4 - 2.007139630671867500 * g11;
        gto[4*ngrids+grid_id] = 0.317356640745612911 * g0 + 0.634713281491225822 * g3 - 2.538853125964903290 * g5 + 0.317356640745612911 * g10 - 2.538853125964903290 * g12 + 0.846284375321634430 * g14;
        gto[5*ngrids+grid_id] = 2.676186174229156671 * g9 - 2.007139630671867500 * g2 - 2.007139630671867500 * g7 ;
        gto[6*ngrids+grid_id] = 2.838524087272680054 * g5 + 0.473087347878780009 * g10- 0.473087347878780002 * g0 - 2.838524087272680050 * g12;
        gto[7*ngrids+grid_id] = 1.770130769779930531 * g2 - 5.310392309339791590 * g7 ;
        gto[8*ngrids+grid_id] = 0.625835735449176134 * g0 - 3.755014412695056800 * g3 + 0.625835735449176134 * g10;
    }
}


template <int ANG> __global__
static void _sph_kernel_deriv1(BasOffsets offsets)
{
    int ngrids = offsets.ngrids;
    int grid_id = blockIdx.x * blockDim.x + threadIdx.x;
    if (grid_id >= ngrids) {
        return;
    }

    int bas_id = blockIdx.y;
    int natm = c_envs.natm;
    int nbas = c_envs.nbas;
    int nao = c_envs.ao_loc[nbas];
    int ish = offsets.bas_off + bas_id;
    int atm_id = c_bas_atom[ish];
    size_t i0 = c_envs.ao_loc[ish];
    double* __restrict__ gto = offsets.data + i0 * ngrids;
    double* __restrict__ gtox = offsets.data + (nao * 1 + i0) * ngrids;
    double* __restrict__ gtoy = offsets.data + (nao * 2 + i0) * ngrids;
    double* __restrict__ gtoz = offsets.data + (nao * 3 + i0) * ngrids;

    double *atom_coordx = c_envs.atom_coordx;
    double *atom_coordy = c_envs.atom_coordx + natm;
    double *atom_coordz = c_envs.atom_coordx + natm * 2;
    double *gridx = offsets.gridx;
    double *gridy = offsets.gridx + ngrids;
    double *gridz = offsets.gridx + ngrids * 2;
    double rx = gridx[grid_id] - atom_coordx[atm_id];
    double ry = gridy[grid_id] - atom_coordy[atm_id];
    double rz = gridz[grid_id] - atom_coordz[atm_id];
    double rr = rx * rx + ry * ry + rz * rz;
    double *exps = c_envs.env + c_bas_exp[ish];
    double *coeffs = c_envs.env + c_bas_coeff[ish];

    double ce = 0;
    double ce_2a = 0;
    for (int ip = 0; ip < offsets.nprim; ++ip) {
        double c = coeffs[ip];
        double e = exp(-exps[ip] * rr);
        ce += c * e;
        ce_2a += c * e * exps[ip];
    }
    ce *= offsets.fac;
    ce_2a *= -2 * offsets.fac;

    if (ANG == 2) {
        double ax = ce_2a * rx;
        double ay = ce_2a * ry;
        double az = ce_2a * rz;
        double bx = ce * rx;
        double by = ce * ry;
        double bz = ce * rz;
        double g0 = ce * rx * rx;
        double g1 = ce * rx * ry;
        double g2 = ce * rx * rz;
        double g3 = ce * ry * ry;
        double g4 = ce * ry * rz;
        double g5 = ce * rz * rz;
        gto[         grid_id] = 1.092548430592079070 * g1;
        gto[1*ngrids+grid_id] = 1.092548430592079070 * g4;
        gto[2*ngrids+grid_id] = 0.630783130505040012 * g5 - 0.315391565252520002 * g0 - 0.315391565252520002 * g3;
        gto[3*ngrids+grid_id] = 1.092548430592079070 * g2;
        gto[4*ngrids+grid_id] = 0.546274215296039535 * g0 - 0.546274215296039535 * g3;
        g0 = ax * rx * rx + 2 * bx;
        g1 = ax * rx * ry +     by;
        g2 = ax * rx * rz +     bz;
        g3 = ax * ry * ry;
        g4 = ax * ry * rz;
        g5 = ax * rz * rz;
        gtox[         grid_id] = 1.092548430592079070 * g1;
        gtox[1*ngrids+grid_id] = 1.092548430592079070 * g4;
        gtox[2*ngrids+grid_id] = 0.630783130505040012 * g5 - 0.315391565252520002 * g0 - 0.315391565252520002 * g3;
        gtox[3*ngrids+grid_id] = 1.092548430592079070 * g2;
        gtox[4*ngrids+grid_id] = 0.546274215296039535 * g0 - 0.546274215296039535 * g3;
        g0 = ay * rx * rx;
        g1 = ay * rx * ry +     bx;
        g2 = ay * rx * rz;
        g3 = ay * ry * ry + 2 * by;
        g4 = ay * ry * rz +     bz;
        g5 = ay * rz * rz;
        gtoy[         grid_id] = 1.092548430592079070 * g1;
        gtoy[1*ngrids+grid_id] = 1.092548430592079070 * g4;
        gtoy[2*ngrids+grid_id] = 0.630783130505040012 * g5 - 0.315391565252520002 * g0 - 0.315391565252520002 * g3;
        gtoy[3*ngrids+grid_id] = 1.092548430592079070 * g2;
        gtoy[4*ngrids+grid_id] = 0.546274215296039535 * g0 - 0.546274215296039535 * g3;
        g0 = az * rx * rx;
        g1 = az * rx * ry;
        g2 = az * rx * rz +     bx;
        g3 = az * ry * ry;
        g4 = az * ry * rz +     by;
        g5 = az * rz * rz + 2 * bz;
        gtoz[         grid_id] = 1.092548430592079070 * g1;
        gtoz[1*ngrids+grid_id] = 1.092548430592079070 * g4;
        gtoz[2*ngrids+grid_id] = 0.630783130505040012 * g5 - 0.315391565252520002 * g0 - 0.315391565252520002 * g3;
        gtoz[3*ngrids+grid_id] = 1.092548430592079070 * g2;
        gtoz[4*ngrids+grid_id] = 0.546274215296039535 * g0 - 0.546274215296039535 * g3;
    } else if (ANG == 3) {
        double ax = ce_2a * rx;
        double ay = ce_2a * ry;
        double az = ce_2a * rz;
        double bxx = ce * rx * rx;
        double bxy = ce * rx * ry;
        double bxz = ce * rx * rz;
        double byy = ce * ry * ry;
        double byz = ce * ry * rz;
        double bzz = ce * rz * rz;
        double g0 = ce * rx * rx * rx;
        double g1 = ce * rx * rx * ry;
        double g2 = ce * rx * rx * rz;
        double g3 = ce * rx * ry * ry;
        double g4 = ce * rx * ry * rz;
        double g5 = ce * rx * rz * rz;
        double g6 = ce * ry * ry * ry;
        double g7 = ce * ry * ry * rz;
        double g8 = ce * ry * rz * rz;
        double g9 = ce * rz * rz * rz;
        gto[         grid_id] = 1.770130769779930531 * g1 - 0.590043589926643510 * g6;
        gto[1*ngrids+grid_id] = 2.890611442640554055 * g4;
        gto[2*ngrids+grid_id] = 1.828183197857862944 * g8 - 0.457045799464465739 * g1 - 0.457045799464465739 * g6;
        gto[3*ngrids+grid_id] = 0.746352665180230782 * g9 - 1.119528997770346170 * g2 - 1.119528997770346170 * g7;
        gto[4*ngrids+grid_id] = 1.828183197857862944 * g5 - 0.457045799464465739 * g0 - 0.457045799464465739 * g3;
        gto[5*ngrids+grid_id] = 1.445305721320277020 * g2 - 1.445305721320277020 * g7;
        gto[6*ngrids+grid_id] = 0.590043589926643510 * g0 - 1.770130769779930530 * g3;
        g0 = ax * rx * rx * rx + 3 * bxx;
        g1 = ax * rx * rx * ry + 2 * bxy;
        g2 = ax * rx * rx * rz + 2 * bxz;
        g3 = ax * rx * ry * ry +     byy;
        g4 = ax * rx * ry * rz +     byz;
        g5 = ax * rx * rz * rz +     bzz;
        g6 = ax * ry * ry * ry;
        g7 = ax * ry * ry * rz;
        g8 = ax * ry * rz * rz;
        g9 = ax * rz * rz * rz;
        gtox[         grid_id] = 1.770130769779930531 * g1 - 0.590043589926643510 * g6;
        gtox[1*ngrids+grid_id] = 2.890611442640554055 * g4;
        gtox[2*ngrids+grid_id] = 1.828183197857862944 * g8 - 0.457045799464465739 * g1 - 0.457045799464465739 * g6;
        gtox[3*ngrids+grid_id] = 0.746352665180230782 * g9 - 1.119528997770346170 * g2 - 1.119528997770346170 * g7;
        gtox[4*ngrids+grid_id] = 1.828183197857862944 * g5 - 0.457045799464465739 * g0 - 0.457045799464465739 * g3;
        gtox[5*ngrids+grid_id] = 1.445305721320277020 * g2 - 1.445305721320277020 * g7;
        gtox[6*ngrids+grid_id] = 0.590043589926643510 * g0 - 1.770130769779930530 * g3;
        g0 = ay * rx * rx * rx;
        g1 = ay * rx * rx * ry +     bxx;
        g2 = ay * rx * rx * rz;
        g3 = ay * rx * ry * ry + 2 * bxy;
        g4 = ay * rx * ry * rz +     bxz;
        g5 = ay * rx * rz * rz;
        g6 = ay * ry * ry * ry + 3 * byy;
        g7 = ay * ry * ry * rz + 2 * byz;
        g8 = ay * ry * rz * rz +     bzz;
        g9 = ay * rz * rz * rz;
        gtoy[         grid_id] = 1.770130769779930531 * g1 - 0.590043589926643510 * g6;
        gtoy[1*ngrids+grid_id] = 2.890611442640554055 * g4;
        gtoy[2*ngrids+grid_id] = 1.828183197857862944 * g8 - 0.457045799464465739 * g1 - 0.457045799464465739 * g6;
        gtoy[3*ngrids+grid_id] = 0.746352665180230782 * g9 - 1.119528997770346170 * g2 - 1.119528997770346170 * g7;
        gtoy[4*ngrids+grid_id] = 1.828183197857862944 * g5 - 0.457045799464465739 * g0 - 0.457045799464465739 * g3;
        gtoy[5*ngrids+grid_id] = 1.445305721320277020 * g2 - 1.445305721320277020 * g7;
        gtoy[6*ngrids+grid_id] = 0.590043589926643510 * g0 - 1.770130769779930530 * g3;
        g0 = az * rx * rx * rx;
        g1 = az * rx * rx * ry;
        g2 = az * rx * rx * rz +     bxx;
        g3 = az * rx * ry * ry;
        g4 = az * rx * ry * rz +     bxy;
        g5 = az * rx * rz * rz + 2 * bxz;
        g6 = az * ry * ry * ry;
        g7 = az * ry * ry * rz +     byy;
        g8 = az * ry * rz * rz + 2 * byz;
        g9 = az * rz * rz * rz + 3 * bzz;
        gtoz[         grid_id] = 1.770130769779930531 * g1 - 0.590043589926643510 * g6;
        gtoz[1*ngrids+grid_id] = 2.890611442640554055 * g4;
        gtoz[2*ngrids+grid_id] = 1.828183197857862944 * g8 - 0.457045799464465739 * g1 - 0.457045799464465739 * g6;
        gtoz[3*ngrids+grid_id] = 0.746352665180230782 * g9 - 1.119528997770346170 * g2 - 1.119528997770346170 * g7;
        gtoz[4*ngrids+grid_id] = 1.828183197857862944 * g5 - 0.457045799464465739 * g0 - 0.457045799464465739 * g3;
        gtoz[5*ngrids+grid_id] = 1.445305721320277020 * g2 - 1.445305721320277020 * g7;
        gtoz[6*ngrids+grid_id] = 0.590043589926643510 * g0 - 1.770130769779930530 * g3;
    } else if (ANG == 4) {
        double ax = ce_2a * rx;
        double ay = ce_2a * ry;
        double az = ce_2a * rz;
        double bxxx = ce * rx * rx * rx;
        double bxxy = ce * rx * rx * ry;
        double bxxz = ce * rx * rx * rz;
        double bxyy = ce * rx * ry * ry;
        double bxyz = ce * rx * ry * rz;
        double bxzz = ce * rx * rz * rz;
        double byyy = ce * ry * ry * ry;
        double byyz = ce * ry * ry * rz;
        double byzz = ce * ry * rz * rz;
        double bzzz = ce * rz * rz * rz;
        double g0  = ce * rx * rx * rx * rx;
        double g1  = ce * rx * rx * rx * ry;
        double g2  = ce * rx * rx * rx * rz;
        double g3  = ce * rx * rx * ry * ry;
        double g4  = ce * rx * rx * ry * rz;
        double g5  = ce * rx * rx * rz * rz;
        double g6  = ce * rx * ry * ry * ry;
        double g7  = ce * rx * ry * ry * rz;
        double g8  = ce * rx * ry * rz * rz;
        double g9  = ce * rx * rz * rz * rz;
        double g10 = ce * ry * ry * ry * ry;
        double g11 = ce * ry * ry * ry * rz;
        double g12 = ce * ry * ry * rz * rz;
        double g13 = ce * ry * rz * rz * rz;
        double g14 = ce * rz * rz * rz * rz;
        gto[          grid_id] = 2.503342941796704538 * g1 - 2.503342941796704530 * g6 ;
        gto[1 *ngrids+grid_id] = 5.310392309339791593 * g4 - 1.770130769779930530 * g11;
        gto[2 *ngrids+grid_id] = 5.677048174545360108 * g8 - 0.946174695757560014 * g1 - 0.946174695757560014 * g6 ;
        gto[3 *ngrids+grid_id] = 2.676186174229156671 * g13 - 2.007139630671867500 * g4 - 2.007139630671867500 * g11;
        gto[4 *ngrids+grid_id] = 0.317356640745612911 * g0 + 0.634713281491225822 * g3 - 2.538853125964903290 * g5 + 0.317356640745612911 * g10 - 2.538853125964903290 * g12 + 0.846284375321634430 * g14;
        gto[5 *ngrids+grid_id] = 2.676186174229156671 * g9 - 2.007139630671867500 * g2 - 2.007139630671867500 * g7 ;
        gto[6 *ngrids+grid_id] = 2.838524087272680054 * g5 + 0.473087347878780009 * g10 - 0.473087347878780002 * g0 - 2.838524087272680050 * g12;
        gto[7 *ngrids+grid_id] = 1.770130769779930531 * g2 - 5.310392309339791590 * g7 ;
        gto[8 *ngrids+grid_id] = 0.625835735449176134 * g0 - 3.755014412695056800 * g3 + 0.625835735449176134 * g10;
        g0  = ax * rx * rx * rx * rx + 4 * bxxx;
        g1  = ax * rx * rx * rx * ry + 3 * bxxy;
        g2  = ax * rx * rx * rx * rz + 3 * bxxz;
        g3  = ax * rx * rx * ry * ry + 2 * bxyy;
        g4  = ax * rx * rx * ry * rz + 2 * bxyz;
        g5  = ax * rx * rx * rz * rz + 2 * bxzz;
        g6  = ax * rx * ry * ry * ry +     byzz;
        g7  = ax * rx * ry * ry * rz +     byzz;
        g8  = ax * rx * ry * rz * rz +     byzz;
        g9  = ax * rx * rz * rz * rz +     bzzz;
        g10 = ax * ry * ry * ry * ry;
        g11 = ax * ry * ry * ry * rz;
        g12 = ax * ry * ry * rz * rz;
        g13 = ax * ry * rz * rz * rz;
        g14 = ax * rz * rz * rz * rz;
        gtox[          grid_id] = 2.503342941796704538 * g1 - 2.503342941796704530 * g6 ;
        gtox[1 *ngrids+grid_id] = 5.310392309339791593 * g4 - 1.770130769779930530 * g11;
        gtox[2 *ngrids+grid_id] = 5.677048174545360108 * g8 - 0.946174695757560014 * g1 - 0.946174695757560014 * g6 ;
        gtox[3 *ngrids+grid_id] = 2.676186174229156671 * g13 - 2.007139630671867500 * g4 - 2.007139630671867500 * g11;
        gtox[4 *ngrids+grid_id] = 0.317356640745612911 * g0 + 0.634713281491225822 * g3 - 2.538853125964903290 * g5 + 0.317356640745612911 * g10 - 2.538853125964903290 * g12 + 0.846284375321634430 * g14;
        gtox[5 *ngrids+grid_id] = 2.676186174229156671 * g9 - 2.007139630671867500 * g2 - 2.007139630671867500 * g7 ;
        gtox[6 *ngrids+grid_id] = 2.838524087272680054 * g5 + 0.473087347878780009 * g10 - 0.473087347878780002 * g0 - 2.838524087272680050 * g12;
        gtox[7 *ngrids+grid_id] = 1.770130769779930531 * g2 - 5.310392309339791590 * g7 ;
        gtox[8 *ngrids+grid_id] = 0.625835735449176134 * g0 - 3.755014412695056800 * g3 + 0.625835735449176134 * g10;
        g0  = ay * rx * rx * rx * rx;          
        g1  = ay * rx * rx * rx * ry +     bxxx;
        g2  = ay * rx * rx * rx * rz;
        g3  = ay * rx * rx * ry * ry + 2 * bxxy;
        g4  = ay * rx * rx * ry * rz +     bxxz;
        g5  = ay * rx * rx * rz * rz;
        g6  = ay * rx * ry * ry * ry + 3 * bxyy;
        g7  = ay * rx * ry * ry * rz + 2 * bxyz;
        g8  = ay * rx * ry * rz * rz +     bxzz;
        g9  = ay * rx * rz * rz * rz;
        g10 = ay * ry * ry * ry * ry + 4 * byyy;
        g11 = ay * ry * ry * ry * rz + 3 * byyz;
        g12 = ay * ry * ry * rz * rz + 2 * byzz;
        g13 = ay * ry * rz * rz * rz +     bzzz;
        g14 = ay * rz * rz * rz * rz;          
        gtoy[          grid_id] = 2.503342941796704538 * g1 - 2.503342941796704530 * g6 ;
        gtoy[1 *ngrids+grid_id] = 5.310392309339791593 * g4 - 1.770130769779930530 * g11;
        gtoy[2 *ngrids+grid_id] = 5.677048174545360108 * g8 - 0.946174695757560014 * g1 - 0.946174695757560014 * g6 ;
        gtoy[3 *ngrids+grid_id] = 2.676186174229156671 * g13 - 2.007139630671867500 * g4 - 2.007139630671867500 * g11;
        gtoy[4 *ngrids+grid_id] = 0.317356640745612911 * g0 + 0.634713281491225822 * g3 - 2.538853125964903290 * g5 + 0.317356640745612911 * g10 - 2.538853125964903290 * g12 + 0.846284375321634430 * g14;
        gtoy[5 *ngrids+grid_id] = 2.676186174229156671 * g9 - 2.007139630671867500 * g2 - 2.007139630671867500 * g7 ;
        gtoy[6 *ngrids+grid_id] = 2.838524087272680054 * g5 + 0.473087347878780009 * g10 - 0.473087347878780002 * g0 - 2.838524087272680050 * g12;
        gtoy[7 *ngrids+grid_id] = 1.770130769779930531 * g2 - 5.310392309339791590 * g7 ;
        gtoy[8 *ngrids+grid_id] = 0.625835735449176134 * g0 - 3.755014412695056800 * g3 + 0.625835735449176134 * g10;
        g0  = az * rx * rx * rx * rx;
        g1  = az * rx * rx * rx * ry;
        g2  = az * rx * rx * rx * rz +     bxxx;
        g3  = az * rx * rx * ry * ry; 
        g4  = az * rx * rx * ry * rz +     bxxy;
        g5  = az * rx * rx * rz * rz + 2 * bxxz;
        g6  = az * rx * ry * ry * ry;
        g7  = az * rx * ry * ry * rz +     bxyy;
        g8  = az * rx * ry * rz * rz + 2 * bxyz;
        g9  = az * rx * rz * rz * rz + 3 * bxzz;
        g10 = az * ry * ry * ry * ry;
        g11 = az * ry * ry * ry * rz +     byyy;
        g12 = az * ry * ry * rz * rz + 2 * byyz;
        g13 = az * ry * rz * rz * rz + 3 * byzz;
        g14 = az * rz * rz * rz * rz + 4 * bzzz;
        gtoz[          grid_id] = 2.503342941796704538 * g1 - 2.503342941796704530 * g6 ;
        gtoz[1 *ngrids+grid_id] = 5.310392309339791593 * g4 - 1.770130769779930530 * g11;
        gtoz[2 *ngrids+grid_id] = 5.677048174545360108 * g8 - 0.946174695757560014 * g1 - 0.946174695757560014 * g6 ;
        gtoz[3 *ngrids+grid_id] = 2.676186174229156671 * g13 - 2.007139630671867500 * g4 - 2.007139630671867500 * g11;
        gtoz[4 *ngrids+grid_id] = 0.317356640745612911 * g0 + 0.634713281491225822 * g3 - 2.538853125964903290 * g5 + 0.317356640745612911 * g10 - 2.538853125964903290 * g12 + 0.846284375321634430 * g14;
        gtoz[5 *ngrids+grid_id] = 2.676186174229156671 * g9 - 2.007139630671867500 * g2 - 2.007139630671867500 * g7 ;
        gtoz[6 *ngrids+grid_id] = 2.838524087272680054 * g5 + 0.473087347878780009 * g10 - 0.473087347878780002 * g0 - 2.838524087272680050 * g12;
        gtoz[7 *ngrids+grid_id] = 1.770130769779930531 * g2 - 5.310392309339791590 * g7 ;
        gtoz[8 *ngrids+grid_id] = 0.625835735449176134 * g0 - 3.755014412695056800 * g3 + 0.625835735449176134 * g10;
    }
}

extern "C" {
__host__
void GDFTinit_envs(GTOValEnvVars **envs_cache, int *ao_loc,
                   int *atm, int natm, int *bas, int nbas, double *env, int nenv)
{
    assert(nbas < NBAS_MAX);

    GTOValEnvVars *envs = (GTOValEnvVars *)malloc(sizeof(GTOValEnvVars));
    *envs_cache = envs;
    envs->natm = natm;
    envs->nbas = nbas;

    DEVICE_INIT(int, d_ao_loc, ao_loc, nbas+1);
    envs->ao_loc = d_ao_loc;

    DEVICE_INIT(double, d_env, env, nenv);
    envs->env = d_env;

    double *atom_coords = (double *)malloc(sizeof(double) * natm * 3);
    int ia, ptr;
    for (ia = 0; ia < natm; ++ia) {
        ptr = atm[PTR_COORD + ATM_SLOTS*ia];
        atom_coords[       ia] = env[ptr+0];
        atom_coords[  natm+ia] = env[ptr+1];
        atom_coords[2*natm+ia] = env[ptr+2];
    }
    DEVICE_INIT(double, d_atom_coords, atom_coords, natm * 3);
    envs->atom_coordx = d_atom_coords;

    uint16_t bas_atom[NBAS_MAX];
    uint16_t bas_exp[NBAS_MAX];
    uint16_t bas_coeff[NBAS_MAX];
    int ish;
    for (ish = 0; ish < nbas; ++ish) {
        bas_atom[ish] = bas[ATOM_OF + ish * BAS_SLOTS];
        bas_exp[ish] = bas[PTR_EXP + ish * BAS_SLOTS];
        bas_coeff[ish] = bas[PTR_COEFF + ish * BAS_SLOTS];
    }

    checkCudaErrors(cudaMemcpyToSymbol(c_envs, envs, sizeof(GTOValEnvVars)));
    checkCudaErrors(cudaMemcpyToSymbol(c_bas_atom, bas_atom, sizeof(uint16_t)*NBAS_MAX));
    checkCudaErrors(cudaMemcpyToSymbol(c_bas_exp, bas_exp, sizeof(uint16_t)*NBAS_MAX));
    checkCudaErrors(cudaMemcpyToSymbol(c_bas_coeff, bas_coeff, sizeof(uint16_t)*NBAS_MAX));
}

void GDFTdel_envs(GTOValEnvVars **envs_cache)
{
    GTOValEnvVars *envs = *envs_cache;
    if (envs == NULL) {
        return;
    }

    FREE(envs->ao_loc);
    FREE(envs->env);
    FREE(envs->atom_coordx);

    free(envs);
    *envs_cache = NULL;
}

double CINTcommon_fac_sp(int l);

int GDFTeval_gto(double *ao, int deriv, int cart,
                 double *grids, int ngrids, int *bas_loc, int nbuckets,
                 int *atm, int natm, int *bas, int nbas, double *env)
{
    BasOffsets offsets;
    DEVICE_INIT(double, d_grids, grids, ngrids * 3);
    offsets.gridx = d_grids;
    offsets.ngrids = ngrids;
    offsets.data = ao;

    dim3 threads(THREADS);
    dim3 blocks((ngrids+THREADS-1)/THREADS);

    for (int bucket = 0; bucket < nbuckets; ++bucket) {
        int ish = bas_loc[bucket];
        int l = bas[ANG_OF+ish*BAS_SLOTS];
        offsets.bas_off = ish;
        offsets.nprim = bas[NPRIM_OF+ish*BAS_SLOTS];
        offsets.fac = CINTcommon_fac_sp(l);
        blocks.y = bas_loc[bucket+1] - ish;

        switch (deriv) {
        case 0:
            if (cart == 1) {
                switch (l) {
                case 0: _cart_kernel_deriv0<0> <<<blocks, threads>>>(offsets); break;
                case 1: _cart_kernel_deriv0<1> <<<blocks, threads>>>(offsets); break;
                case 2: _cart_kernel_deriv0<2> <<<blocks, threads>>>(offsets); break;
                case 3: _cart_kernel_deriv0<3> <<<blocks, threads>>>(offsets); break;
                case 4: _cart_kernel_deriv0<4> <<<blocks, threads>>>(offsets); break;
                default: fprintf(stderr, "l = %d not supported\n", l); }
            } else {
                switch (l) {
                case 0: _cart_kernel_deriv0<0> <<<blocks, threads>>>(offsets); break;
                case 1: _cart_kernel_deriv0<1> <<<blocks, threads>>>(offsets); break;
                case 2: _sph_kernel_deriv0 <2> <<<blocks, threads>>>(offsets); break;
                case 3: _sph_kernel_deriv0 <3> <<<blocks, threads>>>(offsets); break;
                case 4: _sph_kernel_deriv0 <4> <<<blocks, threads>>>(offsets); break;
                default: fprintf(stderr, "l = %d not supported\n", l); }
            }
            break;
        case 1:
            if (cart == 1) {
                switch (l) {
                case 0: _cart_kernel_deriv1<0> <<<blocks, threads>>>(offsets); break;
                case 1: _cart_kernel_deriv1<1> <<<blocks, threads>>>(offsets); break;
                case 2: _cart_kernel_deriv1<2> <<<blocks, threads>>>(offsets); break;
                case 3: _cart_kernel_deriv1<3> <<<blocks, threads>>>(offsets); break;
                case 4: _cart_kernel_deriv1<4> <<<blocks, threads>>>(offsets); break;
                default: fprintf(stderr, "l = %d not supported\n", l); }
            } else {
                switch (l) {
                case 0: _cart_kernel_deriv1<0> <<<blocks, threads>>>(offsets); break;
                case 1: _cart_kernel_deriv1<1> <<<blocks, threads>>>(offsets); break;
                case 2: _sph_kernel_deriv1 <2> <<<blocks, threads>>>(offsets); break;
                case 3: _sph_kernel_deriv1 <3> <<<blocks, threads>>>(offsets); break;
                case 4: _sph_kernel_deriv1 <4> <<<blocks, threads>>>(offsets); break;
                default: fprintf(stderr, "l = %d not supported\n", l); }
            }
            break;
        default:
            fprintf(stderr, "deriv %d not supported\n", deriv);
            return 1;
        }
        cudaError_t err = cudaGetLastError();
        if (err != cudaSuccess) {
            fprintf(stderr, "CUDA Error of GDFTeval_gto_kernel: %s\n", cudaGetErrorString(err));
            return 1;
        }
    }
    FREE(d_grids);
    return 0;
}

int GDFTcontract_rho(double *rho, double *bra, double *ket, int ngrids, int nao)
{
    dim3 threads(BLKSIZEX, BLKSIZEY);
    dim3 blocks((ngrids+BLKSIZEX-1)/BLKSIZEX);
    GDFTcontract_rho_kernel<<<blocks, threads>>>(rho, bra, ket, ngrids, nao);
    cudaError_t err = cudaGetLastError();
    if (err != cudaSuccess) {
        fprintf(stderr, "CUDA Error of GDFTcontract_rho: %s\n", cudaGetErrorString(err));
        return 1;
    }
    return 0;
}

int GDFTscale_ao(double *out, double *ket, double *wv,
                 int ngrids, int nao, int nvar)
{
    dim3 threads(BLKSIZEX, BLKSIZEY);
    dim3 blocks((ngrids+BLKSIZEX-1)/BLKSIZEX, (nao+BLKSIZEY-1)/BLKSIZEY);
    GDFTscale_ao_kernel<<<blocks, threads>>>(out, ket, wv, ngrids, nao, nvar);
    cudaError_t err = cudaGetLastError();
    if (err != cudaSuccess) {
        fprintf(stderr, "CUDA Error of GDFTscale_ao: %s\n", cudaGetErrorString(err));
        return 1;
    }
    return 0;
}
}

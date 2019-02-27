{-
TorXakis - Model Based Testing
Copyright (c) 2015-2017 TNO and Radboud University
See LICENSE at root directory of this repository.
-}
-----------------------------------------------------------------------------
-- |
-- Module      :  TorXakis.ContextTestVar
-- Copyright   :  (c) TNO and Radboud University
-- License     :  BSD3 (see the file license.txt)
-- 
-- Maintainer  :  pierre.vandelaar@tno.nl (ESI)
-- Stability   :  experimental
-- Portability :  portable
--
-- Var Context for Test: 
-- Additional functionality to ensure termination for QuickCheck
-----------------------------------------------------------------------------
module TorXakis.ContextTestVar
(-- * Context Test Var
  ContextTestVar
, TorXakis.ContextTestVar.empty
, TorXakis.ContextTestVar.fromSortContext
)
where
import           TorXakis.ContextVar
import           TorXakis.VarContext
import           TorXakis.TestSortContext
import           TorXakis.TestVarContext
import           TorXakis.TestVarData


-- | An instance of 'TestVarContext'.
data ContextTestVar = ContextTestVar { basis :: ContextVar
                                     , tvd :: TestVarData
                                     }

-- | empty constructor
empty :: ContextTestVar
empty = ContextTestVar TorXakis.ContextVar.empty TorXakis.TestVarData.empty

-- | Constructor from SortContext
fromSortContext :: SortContext b => b -> ContextTestVar
fromSortContext ctx = let nctx = TorXakis.ContextVar.fromSortContext ctx in
                        ContextTestVar nctx (TorXakis.TestVarData.afterAddADTs nctx (elemsADT ctx) TorXakis.TestVarData.empty)

instance SortContext ContextTestVar where
    memberSort r = memberSort r . basis

    memberADT r = memberADT r . basis

    lookupADT r = lookupADT r . basis

    elemsADT  = elemsADT . basis

    addADTs as ctx = case TorXakis.VarContext.addADTs as (basis ctx) of
                          Left e        -> Left e
                          Right basis'  -> Right $ ContextTestVar basis' (TorXakis.TestVarData.afterAddADTs basis' as (tvd ctx))

instance TestSortContext ContextTestVar where
    sortSize s = TorXakis.TestVarData.sortSize s . tvd

    adtSize r = TorXakis.TestVarData.adtSize r . tvd

    constructorSize r c = TorXakis.TestVarData.constructorSize r c . tvd

instance VarContext ContextTestVar where
    memberVar v = memberVar v . basis

    lookupVar v = lookupVar v . basis

    elemsVar  = elemsVar . basis

    addVars vs ctx = case addVars vs (basis ctx) of
                          Left e     -> Left e
                          Right basis' -> Right $ ctx {basis = basis'}

instance TestVarContext ContextTestVar where
    varSize r ctx = TorXakis.TestVarData.varSize r (basis ctx) (tvd ctx)
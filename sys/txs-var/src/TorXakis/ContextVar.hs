{-
TorXakis - Model Based Testing
Copyright (c) 2015-2017 TNO and Radboud University
See LICENSE at root directory of this repository.
-}
-----------------------------------------------------------------------------
-- |
-- Module      :  ContextVar
-- Copyright   :  (c) TNO and Radboud University
-- License     :  BSD3 (see the file license.txt)
--
-- Maintainer  :  pierre.vandelaar@tno.nl (Embedded Systems Innovation by TNO)
-- Stability   :  experimental
-- Portability :  portable
--
-- Context for Variables.
-----------------------------------------------------------------------------
{-# LANGUAGE ExistentialQuantification #-}
module TorXakis.ContextVar
( -- * Context Variable instance
  ContextVar
, TorXakis.ContextVar.empty
, fromSortContext
)
where
import           TorXakis.ContextSort
import           TorXakis.Error
import           TorXakis.Name
import           TorXakis.NameMap
import           TorXakis.SortContext
import           TorXakis.VarContext
import           TorXakis.Var

-- | An instance of 'TorXakis.VarContext'.
data ContextVar = forall a . SortContext a => 
        -- TODO: is this still needed/wanted? we only have one data type that implements interface SortContext: ContextSort....
                            ContextVar { _sortContext :: a -- not used due to compiler
                                         -- variable definitions
                                       , varDefs :: NameMap VarDef
                                       }

-- | empty
empty :: ContextVar
empty = fromSortContext TorXakis.ContextSort.empty

-- | Constructor from SortContext
fromSortContext :: SortContext b => b -> ContextVar
fromSortContext ctx = ContextVar ctx TorXakis.NameMap.empty

instance SortContext ContextVar where
    -- Can't use
    -- memberSort   = memberSort . sortContext
    -- since compiler complains:
    --        * Cannot use record selector `sortContext' as a function due to escaped type variables
    --          Probable fix: use pattern-matching syntax instead
    -- For more info see: https://downloads.haskell.org/~ghc/latest/docs/html/users_guide/glasgow_exts.html?highlight=existentialquantification#extension-ExistentialQuantification
    memberSort r (ContextVar ctx _) = memberSort r ctx

    memberADT r (ContextVar ctx _) = memberADT r ctx

    lookupADT r (ContextVar ctx _) = lookupADT r ctx

    elemsADT (ContextVar ctx _) = elemsADT ctx

    addADTs as (ContextVar ctx vs) = case addADTs as ctx of
                                                Left e     -> Left e
                                                Right sctx -> Right $ ContextVar sctx vs

-- | non unique Variable Definitions (i.e. duplicate names)
nuVarDefs :: [VarDef] -> [VarDef]
nuVarDefs = repeatedByName

-- | undefined Sorts of Variable Definitions.
undefinedSorts :: SortContext a => [VarDef] -> a -> [VarDef]
undefinedSorts vs ctx = filter (not . flip memberSort ctx . sort) vs

instance VarContext ContextVar where
    memberVar v ctx = member v (varDefs ctx)

    lookupVar v ctx = TorXakis.NameMap.lookup v (varDefs ctx)

    elemsVar ctx    = elems (varDefs ctx)

    addVars vs ctx
        | not $ null (nuVarDefs vs)          = Left $ Error ("Non unique variable definitions: " ++ show (nuVarDefs vs))
        | not $ null (undefinedSorts vs ctx) = Left $ Error ("List of variable definitions with undefined sorts: " ++ show (undefinedSorts vs ctx))
        | otherwise                          = Right $ ctx {varDefs = toNameMap vs `union` varDefs ctx}

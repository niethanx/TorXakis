{-
TorXakis - Model Based Testing
Copyright (c) 2015-2017 TNO and Radboud University
See LICENSE at root directory of this repository.
-}
-----------------------------------------------------------------------------
-- |
-- Module      :  FuncTable
-- Copyright   :  (c) TNO and Radboud University
-- License     :  BSD3 (see the file license.txt)
--
-- Maintainer  :  pierre.vandelaar@tno.nl (Embedded Systems Innovation by TNO)
-- Stability   :  experimental
-- Portability :  portable
--
-- This module introduces the context of Sort (collection of all definitions).
-----------------------------------------------------------------------------
{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DeriveGeneric  #-}
{-# LANGUAGE ViewPatterns   #-}

module FuncTable
( Signature (..)
, SignHandler
, Handler
, FuncTable(..)
, FuncTable.empty
, FuncTable.insert
, FuncTable.union
, FuncTable.names
, FuncTable.member
, FuncTable.signatures
, FuncTable.signHandler
)
where

import           Control.DeepSeq
import qualified Data.HashMap.Strict as HMap
import qualified Data.Map.Strict     as Map
import           Data.Maybe
import           Data.Text           (Text)
import           GHC.Generics        (Generic)

import           Sort
import           ValExpr

data Signature = Signature  { sortArgs :: [Sort]
                            , sortRet  :: Sort
                            }
  deriving (Eq, Ord, Read, Show, Generic, NFData)

type Handler v = [ValExpr v] -> ValExpr v

type SignHandler v = Map.Map Signature (Handler v)

-- | Data structure for Function-like Name and Signature to Handler
newtype FuncTable v = FuncTable { toMap :: HMap.HashMap Text (SignHandler v) }
  deriving (Generic, NFData)

instance Show (FuncTable v) where
  show (FuncTable mp) = show $ HMap.keys mp

-- | empty
empty :: FuncTable v
empty = FuncTable HMap.empty

-- | Insert a new name, signature and handler in the table. If the name and
-- signature pair is already present in the table, the associated handler is
-- replaced with the supplied handler.
insert :: Text -> Signature -> Handler v -> FuncTable v -> FuncTable v
insert n s h (toMap -> t) = case HMap.lookup n t of
                                Nothing     ->  FuncTable (HMap.insert n (Map.singleton s h) t)
                                Just m      ->  FuncTable (HMap.insert n (Map.insert s h m)  t)

-- | The expression (@'union' t1 t2@) takes the left-biased union of @t1@ and
-- @t2@. It prefers @t1@ when duplicate name and signature pairs are
-- encountered.
union :: FuncTable v -> FuncTable v -> FuncTable v
union a b = foldl insertSignHandler b (HMap.toList (toMap a))
    where insertSignHandler :: FuncTable v -> (Text, SignHandler v) -> FuncTable v
          insertSignHandler (toMap -> t) (n,sh) = case HMap.lookup n t of
                                Nothing     ->  FuncTable (HMap.insert n sh t)
                                Just m      ->  FuncTable (HMap.insert n (Map.union sh m) t)


-- | Is the name and signature pair a member of the table?
member :: Text -> Signature -> FuncTable v -> Bool
member n s (toMap -> t) = case HMap.lookup n t of
                                Nothing ->  False
                                Just m  ->  Map.member s m

-- | All names of the table
names :: FuncTable v -> [Text]
names (toMap -> t) = HMap.keys t

-- | Get all signatures associated with the given name in the table.
signatures :: Text -> FuncTable v -> [Signature]
signatures n (toMap -> t) = case HMap.lookup n t of
                                Nothing ->  []
                                Just m  ->  Map.keys m


-- | Get signHandler associated with the given name in the table.
signHandler :: Text -> FuncTable v -> SignHandler v
signHandler n (toMap -> t) = fromMaybe Map.empty (HMap.lookup n t)

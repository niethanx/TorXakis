{-
TorXakis - Model Based Testing
Copyright (c) 2015-2017 TNO and Radboud University
See LICENSE at root directory of this repository.
-}
-----------------------------------------------------------------------------
-- |
-- Module      :  Sort.ConstructorDefs
-- Copyright   :  (c) TNO and Radboud University
-- License     :  BSD3 (see the file license.txt)
-- 
-- Maintainer  :  pierre.vandelaar@tno.nl (Embedded Systems Innovation by TNO)
--                kerem.ispirli@tno.nl
-- Stability   :  experimental
-- Portability :  portable
--
-- Definitions for constructors ('ConstructorDef') of ADTs ('ADTDef').
-----------------------------------------------------------------------------
{-# LANGUAGE DeriveAnyClass     #-}
{-# LANGUAGE DeriveDataTypeable #-}
{-# LANGUAGE DeriveGeneric      #-}
{-# LANGUAGE FlexibleInstances     #-}
{-# LANGUAGE MultiParamTypeClasses #-}
module Sort.ConstructorDefs
( -- * Constructors
  -- ** Data structure
  ConstructorDef (..)

-- ** Collection
, ConstructorDefs (..)

-- ** Usage
, constructorDefs

-- * ADT Constructor Errors
, ADTConstructorError (..)
)
where

import           Control.Arrow
import           Control.DeepSeq
import           Data.Data
import           Data.List.Unique
import           Data.List        (intercalate)
import qualified Data.Map.Strict  as Map
import           GHC.Generics     (Generic)

import           Ref
import           Name
import           Sort.ConvertsTo
import           Sort.FieldDefs

-- | Data structure for constructor definition.
data ConstructorDef v = ConstructorDef { constructorName :: Name -- ^ Name of the constructor
                                       , fields :: FieldDefs v   -- ^ Field definitions of the constructor
                                       }
    deriving (Eq,Ord,Read,Show,Generic,NFData,Data)

instance HasName (ConstructorDef v) where
    getName = constructorName
    
-- | Data structure for a collection of 'ConstructorDef's.
newtype ConstructorDefs v = ConstructorDefs { -- | Transform 'ConstructorDefs' to a 'Data.Map.Map' from 'Ref' 'ConstructorDef' to 'ConstructorDef'.
                                              cDefsToMap :: Map.Map (Ref (ConstructorDef v)) (ConstructorDef v)
                                            }
    deriving (Eq,Ord,Read,Show,Generic,NFData,Data)

-- QUESTION: Do we need a smart constructor for 'ConstructorDefs' at all? Are
-- our users going to manipulate constructors that are not associated to an
-- ADT? If not, then we're making things difficult for ourselves. Let's define
-- a smart constructor only for an ADT, and then all the structures below an
-- ADT will be also correctly constructed.

-- | Smart constructor for 'ConstructorDefs'.
--
--   Preconditions:
--
--   * List of 'ConstructorDef's should be non-empty.
--
--   * Names of 'ConstructorDef's should be unique
--
--   * Names of 'FieldDef's should be unique across all 'ConstructorDef's
--
--   Given a list of 'ConstructorDef's,
--
--   * either an error message indicating violations of preconditions
--
--   * or a 'ConstructorDefs' structure containing the constructor definitions
--
--   is returned.
constructorDefs :: [ConstructorDef Name]
                -> Either ADTConstructorError (ConstructorDefs Name)
constructorDefs [] = Left EmptyConstructorDefs
constructorDefs cs
    | not $ null nuCstrNames    = let nonUniqDefs = filter ((`elem` nuCstrNames) . constructorName) cs
                                  in  Left $ ConstructorNamesNotUnique nonUniqDefs
    | not $ null nuFieldNames   = Left $ SameFieldMultipleCstr nuFieldNames
    | otherwise = Right $ ConstructorDefs
                  $ convertTo cs
    where
        nuCstrNames  = repeated $ map constructorName cs
        nuFieldNames = repeated $ map fieldName $ concatMap (fDefsToList . fields) cs

-- | Type of errors that are raised when it's not possible to build a
--   'ConstructorDefs' structure via 'constructorDefs' function.
data ADTConstructorError = ConstructorNamesNotUnique [ConstructorDef Name]
                         | EmptyConstructorDefs
                         | SameFieldMultipleCstr     [Name]
    deriving (Eq)

instance Show ADTConstructorError where
    show (ConstructorNamesNotUnique cDefs) = "Names of following constructor definitions are not unique: " ++ show cDefs
    show  EmptyConstructorDefs             = "No constructor definitions provided."
    show (SameFieldMultipleCstr     names) = "Field names in multiple constructors: "
                                                ++ intercalate ", " (map show names)

instance ConvertsTo a a' => ConvertsTo (ConstructorDef a) (ConstructorDef a') where
    convertTo (ConstructorDef n fs) = ConstructorDef n (convertTo fs)

instance ConvertsTo a a' => ConvertsTo (ConstructorDefs a) (ConstructorDefs a') where
    convertTo (ConstructorDefs csMap) =
        let tuples = Map.toList csMap
            newTuples = map (convertTo *** convertTo) tuples
        in  ConstructorDefs $ Map.fromList newTuples

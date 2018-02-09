{-
TorXakis - Model Based Testing
Copyright (c) 2015-2017 TNO and Radboud University
See LICENSE at root directory of this repository.
-}
{-# LANGUAGE OverloadedStrings      #-}
module TestFieldDefs
(
testFieldList
)
where
-- test specific Haskell imports
import Test.HUnit

-- test specific TorXakis imports

-- generic Haskell imports
import           Data.Either
import qualified Data.Text as T

-- generic TorXakis imports
import Name
import SortInternal
-- ----------------------------------------------------------------------------
testFieldList :: Test
testFieldList =
    TestList [ TestLabel "Single FieldDef" testFDefSingle
             , TestLabel "Multiple FieldDef's" testFDefMultiple
             , TestLabel "No FieldDef's" testEmptyFieldList
             , TestLabel "FieldDef's with same name" testNonUniqueName
             ]
             
---------------------------------------------------------------------------
-- Success cases
---------------------------------------------------------------------------
testFDefSingle :: Test
testFDefSingle = TestCase $ do
    let fList = [fld 1]
    assertEqual "fieldDefs should succeed for single FieldDef"
        (Right $ mkFieldDefs fList) $ fieldDefs fList

testFDefMultiple :: Test
testFDefMultiple = TestCase $ do
    let fList = map fld [1,2,3]
    assertEqual "fieldDefs should succeed for multiple FieldDef's"
        (Right $ mkFieldDefs fList) $ fieldDefs fList

---------------------------------------------------------------------------
-- Pre-condition violation tests
---------------------------------------------------------------------------
testEmptyFieldList :: Test
testEmptyFieldList = TestCase $
    assertEqual "fieldDefs should fail for empty list"
        (Left EmptyDefs) $ fieldDefs []

testNonUniqueName :: Test
testNonUniqueName = TestCase $ do
    let fDef = FieldDef "SameName" SortInt
        fldList = [fDef, fDef]
    assertEqual "fieldDefs should fail for non-unique names"
        (Left $ NamesNotUnique fldList) $ fieldDefs fldList 

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------
fld :: Int -> FieldDef
fld i = fDef
    where
        fDef = FieldDef { fieldName = mkName ("field" ++ show i), sort = SortInt }

mkName :: String -> Name
mkName = fromRight "" . name . T.pack

mkFieldDefs :: [FieldDef] -> FieldDefs
mkFieldDefs fs = FieldDefs fs $ length fs

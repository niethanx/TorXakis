{-
TorXakis - Model Based Testing
Copyright (c) 2015-2017 TNO and Radboud University
See LICENSE at root directory of this repository.
-}
-----------------------------------------------------------------------------
-- |
-- Module      :  SortGenContextSpec
-- Copyright   :  (c) TNO and Radboud University
-- License     :  BSD3 (see the file license.txt)
-- 
-- Maintainer  :  pierre.vandelaar@tno.nl (Embedded Systems Innovation by TNO)
-- Stability   :  experimental
-- Portability :  portable
--
-- Test specifications for 'SortGenContext'.
-----------------------------------------------------------------------------
module TorXakis.SortGenContextSpec
(spec
)
where
import           Test.Hspec
import           Test.QuickCheck

import           TorXakis.Sort
import           TorXakis.SortGenContext
import           TorXakis.TestSortContext

-- | Increments can be combined
prop_Increments :: Gen Bool
prop_Increments = 
    let c0 = empty :: MinimalTestSortContext in do
        incr1 <- arbitraryADTDefs c0
        case addAdtDefs c0 incr1 of
            Left _   -> error "Invalid generator 1"
            Right c1 -> do
                            incr2 <- arbitraryADTDefs c1
                            case addAdtDefs c1 incr2 of
                                Left _   -> error "Invalid generator 2"
                                Right c2 -> return $ case addAdtDefs c0 (incr1++incr2) of
                                                        Left _    -> False
                                                        Right c12 -> c12 == c2

spec :: Spec
spec = do
  describe "A sort gen context" $
    it "incr2 after incr1 == incr2 ++ incr1" $ property prop_Increments

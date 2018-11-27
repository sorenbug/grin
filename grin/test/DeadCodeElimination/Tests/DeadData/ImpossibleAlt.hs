module DeadCodeElimination.Tests.DeadData.ImpossibleAlt where

import System.FilePath

import Grin.Grin

import Test.Hspec
import Test.Assertions

import DeadCodeElimination.Tests.DeadData.Util

(impossibleAltBefore, impossibleAltAfter, impossibleAltSpec) = mkDDETestCase "impossible_alt"
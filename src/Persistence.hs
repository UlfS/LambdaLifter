module Persistence ( readLevelFile ) where
import           Data.Char             (isDigit)
import           Data.List             as L (isPrefixOf)
import           Data.Map              as M (Map, empty, filter, fromList, insert, size)
import           Prelude               as P hiding (lookup)
import           Control.Monad.Error   (catchError)
import           System.FilePath.Posix (takeFileName)

import           Game                  (Level(..), LevelMap, LevelValues(..), Object(..),
 ObjectInitValues(..), charToObject, defaultLevelValues,
 isLambdaLike,
 Result, GameError(..))


-- | Reads a file containing the level description and returns the Level (or an Error)
readLevelFile :: FilePath -> IO (Result Level)
readLevelFile f = do -- IO monad
        c  <- readFile f
        let (lvlString, lvlMetadata)    = splitLevelAndMetadataString . lines $ c
        -- Process metadata
        let lBeardGrowthRate            = extractBeardGrowthRateFromMetadata    (leBeardGrowthRate defaultLevelValues)  lvlMetadata
        let objectInitVals              = ObjectInitValues { oiBeardGrowthRate = lBeardGrowthRate - 1 }
        return $ do -- Error/Either monad
                -- Process level-string
                lMap <- levelStringToMap objectInitVals lvlString `catchError` errorHandler
                return Level { lvName           = levelName
                             , lvMap            = lMap
                             , lvTrampolines    = extractTrampolinesFromMetadata        empty                                   lvlMetadata
                             , lvGrowthRate     = lBeardGrowthRate
                             , lvRazors         = extractRazorsFromMetadata             (leRazors          defaultLevelValues)  lvlMetadata
                             , lvFlooding       = extractFloodingFromMetadata           (leFlooding        defaultLevelValues)  lvlMetadata
                             , lvWater          = extractWaterFromMetadata              (leWater           defaultLevelValues)  lvlMetadata
                             , lvWaterproof     = extractWaterproofFromMetadata         (leWaterproof      defaultLevelValues)  lvlMetadata
                             , lvLambdas        = M.size . M.filter isLambdaLike $ lMap }
        where
        levelName = takeFileName f
        splitLevelAndMetadataString :: [String] -> ([String], [String])
        splitLevelAndMetadataString s = (tFst, P.filter (/= "") tSnd)
                where (tFst, tSnd) = span (/= "") s
        errorHandler (InvalidCharacterError c) = Left (InvalidLevelCharacterError levelName c) -- expanding CharacterError to LevelCharacterError
        errorHandler e                         = Left e  -- do nothing


-- TODO: quick and dirty parsing :(

-- | "Generic" value extraction from a list of strings / metadata description.
--   Takes a function to match the line, 
--   a function to extract the value from that line (with an accumulator of the previous value), 
--   the default value if nothing is found / neutral element and 
--   the list of lines
extractValueFromMetadata :: (line -> Bool) -> (value -> line -> value) -> value -> [line] -> value
extractValueFromMetadata lineCondition extractFromLine = foldl (\d l -> if lineCondition l then extractFromLine d l else d )

-- | Extracts the beard growth rate from the metadata
extractBeardGrowthRateFromMetadata :: Int -> [String] -> Int
extractBeardGrowthRateFromMetadata  = extractValueFromMetadata ("Growth " `isPrefixOf`) (\_ -> read . P.filter isDigit)

-- | Extracts the number of razors from the metadata
extractRazorsFromMetadata :: Int -> [String] -> Int
extractRazorsFromMetadata  = extractValueFromMetadata ("Razors " `isPrefixOf`) (\_ -> read . P.filter isDigit)

-- | Extracts water level from the metadata
extractWaterFromMetadata :: Int -> [String] -> Int
extractWaterFromMetadata  = extractValueFromMetadata ("Water " `isPrefixOf`) (\_ -> read . P.filter isDigit)

-- | Extracts the flooding rate from the metadata
extractFloodingFromMetadata :: Int -> [String] -> Int
extractFloodingFromMetadata  = extractValueFromMetadata ("Flooding " `isPrefixOf`) (\_ -> read . P.filter isDigit)

-- | Extracts the time a robot is waterproof from the metadata
extractWaterproofFromMetadata :: Int -> [String] -> Int
extractWaterproofFromMetadata  = extractValueFromMetadata ("Waterproof " `isPrefixOf`) (\_ -> read . P.filter isDigit)

-- | Extracts a map of trampolines to targets from the metadata
extractTrampolinesFromMetadata :: Map Object Object -> [String] -> Map Object Object
extractTrampolinesFromMetadata = extractValueFromMetadata ("Trampoline " `isPrefixOf`) extract
        where
        extract m l = insert (Trampoline trampo) (Target target) m
                where (trampo:target:_) = P.filter (`elem` ['A' .. 'I'] ++ ['0'..'9']) l


{-
-- Loading without error handling
-levelStringToMap :: ObjectInitValues -> [String] -> LevelMap
-levelStringToMap oiv sl = fromList . concatMap (\(y, s) -> zip [(x,y) | x <- [1..]] (map (charToObject oiv) s)) $ zip [1..] (reverse sl)
-}

-- | Takes the level description as a list of lines and produces a LevelMap - a map containing of the positions and corresponding objects.
--   ObjectInitValues is used to initialize default values for certain objects, like the beard timer
levelStringToMap :: ObjectInitValues -> [String] -> Result LevelMap
levelStringToMap oiv sl = do -- Error/Either monad
        tiles <- mapM numberedLineToPositionObject $ zip [1..] (reverse sl)
        return $ fromList . concat $ tiles
        where
        numberedLineToPositionObject :: (Int, String) -> Result [((Int,Int), Object)]
        numberedLineToPositionObject (y, line) = do -- Error/Either monad
                objectList <- mapM (charToObject oiv) line
                return $ zip [(x,y) | x <- [1..]] objectList
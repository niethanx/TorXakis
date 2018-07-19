{-
TorXakis - Model Based Testing
Copyright (c) 2015-2017 TNO and Radboud University
See LICENSE at root directory of this repository.
-}
{-# LANGUAGE ExistentialQuantification  #-}
{-# LANGUAGE FlexibleContexts           #-}
{-# LANGUAGE FlexibleInstances          #-}
{-# LANGUAGE GeneralizedNewtypeDeriving #-}
{-# LANGUAGE ScopedTypeVariables        #-}
{-# LANGUAGE TypeSynonymInstances       #-}
--------------------------------------------------------------------------------
-- |
-- Module      :  TorXakis.CLI
-- Copyright   :  (c) TNO and Radboud University
-- License     :  BSD3 (see the file license.txt)
--
-- Maintainer  :  damian.nadales@gmail.com (Embedded Systems Innovation by TNO)
-- Stability   :  experimental
-- Portability :  portable
--
-- Command line interface for 'TorXakis'.
--------------------------------------------------------------------------------
module TorXakis.CLI
    ( startCLI
    , module TorXakis.CLI.Env
    , runCli
    )
where

import           Control.Arrow                    ((|||))
import           Control.Concurrent               (threadDelay)
import           Control.Concurrent.Async         (async, cancel)
import           Control.Concurrent.STM.TChan     (TChan, newTChanIO, readTChan,
                                                   tryReadTChan)
import           Control.Concurrent.STM.TVar      (readTVar, readTVarIO,
                                                   writeTVar)
import           Control.Monad                    (forever, unless, void, when)
import           Control.Monad.Except             (runExceptT)
import           Control.Monad.Extra              (whenM)
import           Control.Monad.IO.Class           (MonadIO, liftIO)
import           Control.Monad.Reader             (MonadReader, ReaderT, ask,
                                                   asks, runReaderT)
import           Control.Monad.STM                (atomically, retry)
import           Control.Monad.Trans              (lift)
import           Data.Aeson                       (eitherDecodeStrict)
import qualified Data.ByteString                  as BSS
import qualified Data.ByteString.Char8            as BS
import           Data.Char                        (toLower)
import           Data.Either                      (isLeft)
import           Data.Either.Utils                (maybeToEither)
import           Data.Foldable                    (for_, traverse_)
import           Data.List                        (isInfixOf)
import           Data.List.Split                  (splitOn)
import           Data.Maybe                       (fromMaybe)
import           Data.String.Utils                (strip)
import           Data.Text                        (Text)
import qualified Data.Text                        as T
import           Lens.Micro                       ((^.))
import           System.Console.Haskeline
import           System.Console.Haskeline.History (addHistoryRemovingAllDupes)
import           System.Directory                 (doesFileExist,
                                                   getHomeDirectory)
import           System.FilePath                  ((</>))
import           System.IO                        (BufferMode (NoBuffering),
                                                   Handle,
                                                   IOMode (AppendMode, WriteMode),
                                                   hClose, hFlush, hPutStrLn,
                                                   hSetBuffering, openFile,
                                                   stdout)
import           Text.Read                        (readMaybe)

import           EnvData                          (Msg)
import           TxsShow                          (pshow)

import           TorXakis.CLI.Conf
import           TorXakis.CLI.Env
import           TorXakis.CLI.Help
import qualified TorXakis.CLI.Log                 as Log
import           TorXakis.CLI.WebClient

-- | Client monad
newtype CLIM a = CLIM { innerM :: ReaderT Env IO a }
    deriving ( Functor
             , Applicative
             , Monad
             , MonadIO
             , MonadReader Env
             , MonadException -- needed for getExternalPrint
             )

runCli :: Env -> CLIM a -> IO a
runCli e clim = runReaderT (innerM clim) e

startCLI :: [FilePath] -> CLIM ()
startCLI modelFiles = do
    home <- liftIO getHomeDirectory
    runInputT (haskelineSettings home) cli
  where
    haskelineSettings home = defaultSettings
        { historyFile = Just $ home </> ".torxakis-hist.txt"
        -- We add entries to the history ourselves, by using
        -- 'addHistoryRemovingAllDupes'.
        , autoAddHistory = False
        }

    cli :: InputT CLIM ()
    cli = do
        Log.info "Starting the main loop..."
        outputStrLn $ defaultConf ^. prompt ++ "TorXakis :: Model-based testing"
        withMessages $ \ch ->
            withModelFiles modelFiles $ withInterrupt $
                handleInterrupt (output Nothing ["Ctrl+C: quitting"]) (loop ch)
        liftIO $ hFlush stdout

    withMessages :: (TChan BSS.ByteString -> InputT CLIM ()) -> InputT CLIM ()
    withMessages action = do
        Log.info "Starting printer async..."
        printer <- getExternalPrint
        ch <- liftIO newTChanIO
        env <- lift ask
        sId <- lift $ asks sessionId
        Log.info $ "Enabling messages for session " ++ show sId ++ "..."
        res <- lift openMessages
        when (isLeft res) (error $ show res)
        producer <- liftIO $ async $
            sseSubscribe env ch $ concat ["sessions/", show sId, "/messages"]
        mhT <- lift $ asks fOutH
        Log.info "Triggering action..."
        action ch `finally` do
            Log.info "Closing the messages endpoint..."
            _ <- lift closeMessages
            Log.info "Messages endpoint closed."
            liftIO $ do
                cancel producer
                Log.info "Produced canceled."

    withModelFiles :: [FilePath] -> InputT CLIM () -> InputT CLIM ()
    withModelFiles mfs action = do
        unless (null mfs) $ void $ lift $
            do Log.info $ "Loading model files: " ++ show mfs
               load mfs
        action

outputTillVerdict :: TChan BSS.ByteString -> InputT CLIM ()
outputTillVerdict ch =  do
    bs <- liftIO $ atomically $ readTChan ch
    let msgs = pretty . asTxsMsg $ bs
    traverse_ txsOut msgs
    unless (any hasVerdict msgs) $ outputTillVerdict ch

-- TODO: introduce a "Verdict" type of message in the Msg type.
hasVerdict :: String -> Bool
hasVerdict "PASS"       = True
hasVerdict "No Verdict" = True
hasVerdict s
    | "FAIL: " `isInfixOf` s = True
    | otherwise               = False

printChanContents :: TChan BSS.ByteString -> InputT CLIM ()
printChanContents ch = do
    mbs <- liftIO $ atomically $ tryReadTChan ch
    for_ mbs $ \bs -> do
        traverse_ txsOut (pretty . asTxsMsg $ bs)
        printChanContents ch

txsOut :: String -> InputT CLIM ()
txsOut str = do
    outputStrLn $ prefix ++ str
    -- | Write the output to file as well, if a file handle is open.
    mhT <- lift $ asks fOutH
    mh  <- liftIO $ readTVarIO mhT
    traverse_ printToFile mh
    where
      prefix = defaultConf ^. rPrompt
      printToFile handle = liftIO $
          hPutStrLn handle str >> hFlush handle

txsOuts :: [String] -> InputT CLIM ()
txsOuts = traverse_ txsOut

asTxsMsg :: BS.ByteString -> Either String Msg
asTxsMsg msg = do
    msgData <- maybeToEither dataErr $
               BS.stripPrefix (BS.pack "data:") msg
    eitherDecodeStrict msgData
    where
      dataErr = "The message from TorXakis did not contain a \"data:\" field: "
                ++ show msg

runAndShow :: Outputable a => CLIM a -> InputT CLIM ()
runAndShow act = fmap pretty (lift act) >>= txsOuts

-- | Main loop of the TorXakis CLI.
loop :: TChan BSS.ByteString -> InputT CLIM ()
loop ch = loop'
    where
      loop' = do
          minput <- fmap strip <$> getInputLine (defaultConf ^. prompt)
          Log.info $ "Processing input line: " ++ show (fromMaybe "<no input>" minput)
          case minput of
              Nothing -> loop'
              Just "" -> loop'
              Just "q" -> return ()
              Just "quit" -> return ()
              Just "exit" -> return ()
              Just "x" -> return ()
              Just "?" -> showHelp
              Just "h" -> showHelp
              Just "help" -> showHelp
              Just input ->
                  let strippedInput = strip input
                      (cmdAndArgs, redir) = span (/= '$') strippedInput
                  in do
                      mhT <- lift $ asks fOutH
                      mh <- liftIO $ readTVarIO mhT
                      case mh of
                          Nothing -> return ()
                          Just h -> liftIO $ do hClose h
                                                atomically $ writeTVar mhT Nothing
                      (argsFromFile, mToFileH) <- liftIO $ parseRedirs redir
                      liftIO $ atomically $ writeTVar mhT mToFileH
                      modifyHistory $ addHistoryRemovingAllDupes strippedInput
                      dispatch $ cmdAndArgs ++ argsFromFile
                      loop'

      showHelp :: InputT CLIM ()
      showHelp = do
          outputStrLn helpText
          loop'

      dispatch :: String -> InputT CLIM ()
      dispatch inputLine = do
        Log.info $ "Dispatching input: " ++ inputLine
        runLine inputLine
        printChanContents ch
          where
            runLine :: String -> InputT CLIM ()
            runLine inp =
                let tokens = words inp
                    cmd  = head tokens
                    rest = tail tokens
                in case map toLower cmd of
                    "#"         -> return ()
                    "echo"      -> txsOuts rest
                    "delay"     -> runAndShow (waitFor rest)
                    "i"         -> runAndShow (runExceptT info)
                    "info"      -> runAndShow (runExceptT info)
                    -- TODO: the load command will break if the file names contain a space.
                    "l"         -> runAndShow (load rest)
                    "load"      -> runAndShow (load rest)
                    "param"     -> runAndShow (param rest)
                    "run"       -> run rest
                    "simulator" -> runAndShow (simulator rest)
                    "sim"       -> do
                        runAndShow (sim rest)
                        outputTillVerdict ch
                    "stepper"   -> runAndShow (subStepper rest)
                    "step"      -> do
                        runAndShow (subStep rest)
                        outputTillVerdict ch
                    "tester"    -> runAndShow (tester rest)
                    "test"      -> do
                        runAndShow (test rest)
                        outputTillVerdict ch
                    "stop"      -> runAndShow stopTxs
                    "time"      -> runAndShow (runExceptT getTime)
                    "timer"     -> runAndShow (timer rest)
                    "val"       -> runAndShow (val rest)
                    "var"       -> runAndShow (var rest)
                    "eval"      -> runAndShow (eval rest)
                    "solve"     -> runAndShow (callSolver "sol" rest)
                    "unisolve"  -> runAndShow (callSolver "uni" rest)
                    "ransolve"  -> runAndShow (callSolver "ran" rest)
                    "lpe"       -> runAndShow (callLpe rest)
                    "ncomp"     -> runAndShow (callNComp rest)
                    "show"      -> runAndShow (runExceptT (showTxs rest))
                    "menu"      -> runAndShow (menu rest)
                    "seed"      -> runAndShow (seed rest)
                    "goto"      -> runAndShow (goto rest)
                    "back"      -> runAndShow (back rest)
                    "path"      -> runAndShow (runExceptT getPath)
                    "trace"     -> runAndShow (trace rest)
                    _           -> txsOut $ "Unknown command: '" ++ cmd ++ "'. Try 'help'."
            waitFor :: [String] -> CLIM String
            waitFor [n] = case readMaybe n :: Maybe Int of
                            Nothing -> return $ "Error: " ++ show n ++ " doesn't seem to be an integer."
                            Just s  -> do liftIO $ threadDelay (s * 10 ^ (6 :: Int))
                                          return ""
            waitFor _ = return "Usage: delay <seconds>"
            param :: [String] -> CLIM (Either String String)
            param []    = runExceptT getAllParams
            param [p]   = runExceptT $ getParam p
            param [p,v] = runExceptT $ setParam p v
            param _     = return $ Left "Usage: param [ <parameter> [<value>] ]"
            run :: [String] -> InputT CLIM ()
            run [filePath] = do
                exists <- liftIO $ doesFileExist filePath
                if exists
                    then do fileContents <- liftIO $ readFile filePath
                            let script = lines fileContents
                            traverse_ runLine script
                    else txsOut $ "File " ++ filePath ++ " does not exist."
            run _ = txsOut "Usage: run <file path>"
            simulator :: [String] -> CLIM (Either String ())
            simulator names
                | length names < 2 || length names > 3 = return $ Left "Usage: simulator <model> [<mapper>] <cnect>"
                | otherwise = startSimulator names
            sim :: [String] -> CLIM (Either String ())
            sim []  = simStep "-1"
            sim [n] = simStep n
            sim _   = return $ Left "Usage: sim [<step count>]"
            -- | Sub-command stepper.
            subStepper :: [String] -> CLIM (Either String ())
            subStepper [mName] = stepper mName
            subStepper _       = return $ Left "This command is not supported yet."
            -- | Sub-command step.
            subStep :: [String] -> CLIM (Either String ())
            subStep = step . concat
            tester :: [String] -> CLIM (Either String ())
            tester names
                | length names < 2 || length names > 4 = return $ Left "Usage: tester <model> [<purpose>] [<mapper>] <cnect>"
                | otherwise = startTester names
            test :: [String] -> CLIM (Either String ())
            test = testStep . concat
            timer :: [String] -> CLIM (Either String Text)
            timer [nm] = runExceptT $ callTimer nm
            timer _    = return $ Left "Usage: timer <timer name>"
            val :: [String] -> CLIM (Either String String)
            val [] = runExceptT getVals
            val t  = runExceptT $ createVal $ unwords t
            var :: [String] -> CLIM (Either String String)
            var [] = runExceptT getVars
            var t  = runExceptT $ createVar $ unwords t
            eval :: [String] -> CLIM (Either String String)
            eval [] = return $ Left "Usage: eval <value expression>"
            eval t  = runExceptT $ evaluate $ unwords t
            callSolver :: String -> [String] -> CLIM (Either String String)
            callSolver _   [] = return $ Left "Usage: [uni|ran]solve <value expression>"
            callSolver kind t = runExceptT $ solve kind $ unwords t
            callLpe :: [String] -> CLIM (Either String ())
            callLpe [] = return $ Left "Usage: lpe <model|process>"
            callLpe t  = runExceptT $ lpe $ unwords t
            callNComp :: [String] -> CLIM (Either String ())
            callNComp [] = return $ Left "Usage: ncomp <model>"
            callNComp t  = runExceptT $ ncomp $ unwords t
            menu :: [String] -> CLIM (Either String String)
            menu t = runExceptT $ getMenu $ unwords t
            seed :: [String] -> CLIM (Either String ())
            seed [s] = runExceptT $ setSeed s
            seed _   = return $ Left "Usage: seed <n>"
            goto :: [String] -> CLIM (Either String String)
            goto [st] = case readMaybe st of
                Nothing   -> return $ Left "Usage: goto <state>"
                Just stNr -> runExceptT $ gotoState stNr
            goto _    = return $ Left "Usage: goto <state>"
            back :: [String] -> CLIM (Either String String)
            back []   = runExceptT $ backState 1
            back [st] = case readMaybe st of
                Nothing   -> return $ Left "Usage: back [<count>]"
                Just stNr -> runExceptT $ backState stNr
            back _    = return $ Left "Usage: back [<count>]"
            trace :: [String] -> CLIM (Either String String)
            trace []    = runExceptT $ getTrace ""
            trace [fmt] = runExceptT $ getTrace fmt
            trace _     = return $ Left "Usage: trace [<format>]"

-- | Parse the redirection directories.
parseRedirs :: String -> IO (String, Maybe Handle)
parseRedirs redir = do
    Log.info $ "Parsing redir: " ++ redir
    let redirs = splitOn "$" redir
        (mArgsFn,mOutIOmode,mOutFn) = foldr parseRedir (Nothing, Nothing, Nothing) redirs
    Log.info $ "Parsed redir: " ++ show (mArgsFn,mOutIOmode,mOutFn)
    args <- case mArgsFn of
        Nothing  -> return ""
        Just fin -> readFile fin
    mh <- case mOutFn of
        Nothing -> return Nothing
        Just fn -> case mOutIOmode of
            Nothing     -> error "Impossible to have an out file and no IOMode set!"
            Just ioMode -> do
                fh <- openFile fn ioMode -- TODO: Handle other errors
                hSetBuffering fh NoBuffering
                return $ Just fh
    return (args, mh)
      where
        parseRedir :: String
                   -> (Maybe String, Maybe IOMode, Maybe String)
                   -> (Maybe String, Maybe IOMode, Maybe String)
        parseRedir ('>':'>':fn) (a,_m,_o) = (              a, Just AppendMode, Just $ strip fn)
        parseRedir ('>':fn)     (a,_m,_o) = (              a, Just  WriteMode, Just $ strip fn)
        parseRedir ('<':fn)     (_a,m, o) = (Just $ strip fn,               m,               o)
        parseRedir _            t         = t


-- Consumer:
        -- consumer <- liftIO $ async $ forever $ do
        --     Log.info "Waiting for message..."
        --     msg <- readChan ch
            -- Log.info $ "Printing message: " ++ show msg
            -- mh <- readTVarIO mhT
            -- let prettyMsg = pretty $ asTxsMsg msg
            -- atomically $ do
            --     waiting <- readTVar waitingT
            --     when (waiting && hasVerdict prettyMsg) (writeTVar waitingT False)
            -- traverse_ (outputAndPrint mh printer . ("<< " ++)) prettyMsg

            -- hasVerdict :: [String] -> Bool
            -- hasVerdict = foldl (\ res s -> res || isVerdict s) False
            --   where
            --     isVerdict :: String -> Bool
            --     isVerdict "PASS"       = True
            --     isVerdict "No Verdict" = True
            --     isVerdict s
            --         | "FAIL: " `isInfixOf` s = True
            --         | otherwise               = False

-- | Perform an output action in the @InputT@ monad.
output :: Maybe Handle -> [String] -> InputT CLIM ()
output mh = traverse_ logAndOutput
    where
    logAndOutput s = do
        Log.info $ "Showing output: " ++ s
        case mh of
            Just h  -> liftIO $ do mapM_ (hPutStrLn h) $ lines s -- skip last ending newline
                                   hFlush h
            Nothing -> return ()
        outputStrLn s

-- | Values that can be output in the command line.
class Outputable v where
    -- | Format the value as list of strings, to be printed line by line in the
    -- command line.
    pretty :: v -> [String]

instance Outputable () where
    pretty _ = []

instance Outputable String where
    pretty = pure

instance Outputable [String] where
    pretty = id

instance Outputable Text where
    pretty = pure . T.unpack

instance Outputable Info where
    pretty i = [ "Version: " ++ T.unpack (i ^. version)
               , "Build time: "++ T.unpack (i ^. buildTime)
               ]

instance (Outputable a, Outputable b) => Outputable (Either a b) where
    pretty = pretty ||| pretty

instance Outputable Msg where
    pretty = pure . pshow

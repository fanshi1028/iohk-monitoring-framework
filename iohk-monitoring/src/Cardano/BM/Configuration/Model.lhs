
\subsection{Cardano.BM.Configuration.Model}
\label{code:Cardano.BM.Configuration.Model}

%if style == newcode
\begin{code}
{-# LANGUAGE CPP               #-}
{-# LANGUAGE LambdaCase        #-}
{-# LANGUAGE OverloadedStrings #-}

{-@ LIQUID "--max-case-expand=4" @-}

module Cardano.BM.Configuration.Model
    ( Configuration (..)
    , ConfigurationInternal (..)
    , setup
    , setupFromRepresentation
    , toRepresentation
    , exportConfiguration
    , empty
    , minSeverity
    , setMinSeverity
    , inspectSeverity
    , setSeverity
    , getBackends
    , setBackends
    , getDefaultBackends
    , setDefaultBackends
    , setSetupBackends
    , getSetupBackends
    , getScribes
    , setScribes
    , getCachedScribes
    , setCachedScribes
    , setDefaultScribes
    , setSetupScribes
    , getSetupScribes
    , getAggregatedKind
    , setDefaultAggregatedKind
    , setAggregatedKind
    , getOption
    , findSubTrace
    , setSubTrace
    , getMonitors
    , setMonitors
    , getEKGport
    , setEKGport
    , getGraylogPort
    , setGraylogPort
    , getPrometheusPort
    , setPrometheusPort
    , getGUIport
    , setGUIport
    , getLogOutput
    , setLogOutput
    , testSubTrace
    , evalFilters
    ) where

import           Control.Applicative (Alternative ((<|>)))
import           Control.Concurrent.MVar (MVar, newMVar, readMVar,
                     modifyMVar_)
import           Control.Monad (when)
import           Data.Aeson ((.:))
import           Data.Aeson.Types (parseMaybe)
import qualified Data.HashMap.Strict as HM
import           Data.Maybe (maybe, catMaybes, fromMaybe)
import qualified Data.Text as T
import           Data.Text (Text, pack, unpack)
import qualified Data.Vector as Vector
import           Data.Yaml as Yaml

import           Cardano.BM.Data.AggregatedKind (AggregatedKind(..))
import           Cardano.BM.Data.BackendKind
import qualified Cardano.BM.Data.Configuration as R
import           Cardano.BM.Data.LogItem (LogObject (..), LoggerName, LOContent (..), severity)
import           Cardano.BM.Data.MonitoringEval (MEvExpr, MEvPreCond, MEvAction)
import           Cardano.BM.Data.Output (ScribeDefinition (..), ScribeId,
                     ScribeKind (..))
import           Cardano.BM.Data.Rotation (RotationParameters (..))
import           Cardano.BM.Data.Severity
import           Cardano.BM.Data.SubTrace

\end{code}
%endif

\subsubsection{Configuration.Model}\label{code:Configuration}
\begin{figure}[ht]
\centering{
  \includegraphics[scale=0.54]{ConfigurationModel.pdf}
}
\caption{Configuration model}\label{fig:configuration}
\end{figure}

\begin{code}
type ConfigurationMVar = MVar ConfigurationInternal
newtype Configuration = Configuration
    { getCG :: ConfigurationMVar }

-- Our internal state; see {-"\nameref{fig:configuration}"-}
data ConfigurationInternal = ConfigurationInternal
    { cgMinSeverity       :: Severity
    -- minimum severity level of every object that will be output
    , cgDefRotation       :: Maybe RotationParameters
    -- default rotation parameters
    , cgMapSeverity       :: HM.HashMap LoggerName Severity
    -- severity filter per loggername
    , cgMapSubtrace       :: HM.HashMap LoggerName SubTrace
    -- type of trace per loggername
    , cgOptions           :: HM.HashMap Text Object
    -- options needed for tracing, logging and monitoring
    , cgMapBackend        :: HM.HashMap LoggerName [BackendKind]
    -- backends that will be used for the specific loggername
    , cgDefBackendKs      :: [BackendKind]
    -- backends that will be used if a set of backends for the
    -- specific loggername is not set
    , cgSetupBackends     :: [BackendKind]
    -- backends to setup; every backend to be used must have
    -- been declared here
    , cgMapScribe         :: HM.HashMap LoggerName [ScribeId]
    -- katip scribes that will be used for the specific loggername
    , cgMapScribeCache    :: HM.HashMap LoggerName [ScribeId]
    -- map to cache info of the cgMapScribe
    , cgDefScribes        :: [ScribeId]
    -- katip scribes that will be used if a set of scribes for the
    -- specific loggername is not set
    , cgSetupScribes      :: [ScribeDefinition]
    -- katip scribes to setup; every scribe to be used must have
    -- been declared here
    , cgMapAggregatedKind :: HM.HashMap LoggerName AggregatedKind
    -- kind of Aggregated that will be used for the specific loggername
    , cgDefAggregatedKind :: AggregatedKind
    -- kind of Aggregated that will be used if a set of scribes for the
    -- specific loggername is not set
    , cgMonitors          :: HM.HashMap LoggerName (MEvPreCond, MEvExpr, [MEvAction])
    , cgPortEKG           :: Int
    -- port for EKG server
    , cgPortGraylog       :: Int
    -- port to Graylog server
    , cgPortPrometheus    :: Int
    -- port for Prometheus server
    , cgPortGUI           :: Int
    -- port for changes at runtime
    , cgLogOutput         :: Maybe FilePath
    -- filepath of pipe or file for forwarding of log objects
    } deriving (Show, Eq)

\end{code}

\subsubsection{Backends configured in the |Switchboard|}
For a given context name return the list of backends configured,
or, in case no such configuration exists, return the default backends.
\begin{code}
getBackends :: Configuration -> LoggerName -> IO [BackendKind]
getBackends configuration name = do
    cg <- readMVar $ getCG configuration
    -- let outs = HM.lookup name (cgMapBackend cg)
    -- case outs of
    --     Nothing -> return (cgDefBackendKs cg)
    --     Just os -> return os
    let defs = cgDefBackendKs cg
    let mapbks = cgMapBackend cg
    let find_s [] = defs
        find_s lnames = case HM.lookup (T.intercalate "." lnames) mapbks of
            Nothing -> find_s (init lnames)
            Just os -> os
    return $ find_s $ T.split (=='.') name

getDefaultBackends :: Configuration -> IO [BackendKind]
getDefaultBackends configuration =
    cgDefBackendKs <$> (readMVar $ getCG configuration)

setDefaultBackends :: Configuration -> [BackendKind] -> IO ()
setDefaultBackends configuration bes =
    modifyMVar_ (getCG configuration) $ \cg ->
        return cg { cgDefBackendKs = bes }

setBackends :: Configuration -> LoggerName -> Maybe [BackendKind] -> IO ()
setBackends configuration name be =
    modifyMVar_ (getCG configuration) $ \cg ->
        return cg { cgMapBackend = HM.alter (\_ -> be) name (cgMapBackend cg) }

\end{code}

\subsubsection{Backends to be setup by the |Switchboard|}
Defines the list of |Backend|s that need to be setup by the |Switchboard|.
\begin{code}
setSetupBackends :: Configuration -> [BackendKind] -> IO ()
setSetupBackends configuration bes =
    modifyMVar_ (getCG configuration) $ \cg ->
        return cg { cgSetupBackends = bes }

getSetupBackends :: Configuration -> IO [BackendKind]
getSetupBackends configuration =
    cgSetupBackends <$> (readMVar $ getCG configuration)

\end{code}

\subsubsection{Scribes configured in the |Log| backend}
For a given context name return the list of scribes to output to,
or, in case no such configuration exists, return the default scribes to use.
\begin{code}
getScribes :: Configuration -> LoggerName -> IO [ScribeId]
getScribes configuration name = do
    cg <- readMVar (getCG configuration)
    (updateCache, scribes) <- do
        let defs = cgDefScribes cg
        let mapscribes = cgMapScribe cg
        let find_s [] = defs
            find_s lnames = case HM.lookup (T.intercalate "." lnames) mapscribes of
                Nothing -> find_s (init lnames)
                Just os -> os
        let outs = HM.lookup name (cgMapScribeCache cg)
        -- look if scribes are already cached
        return $ case outs of
            -- if no cached scribes found; search the appropriate scribes that
            -- they must inherit and update the cached map
            Nothing -> (True, find_s $ T.split (=='.') name)
            Just os -> (False, os)

    when updateCache $ setCachedScribes configuration name $ Just scribes
    return scribes

getCachedScribes :: Configuration -> LoggerName -> IO (Maybe [ScribeId])
getCachedScribes configuration name = do
    cg <- readMVar $ getCG configuration
    return $ HM.lookup name $ cgMapScribeCache cg

setScribes :: Configuration -> LoggerName -> Maybe [ScribeId] -> IO ()
setScribes configuration name scribes =
    modifyMVar_ (getCG configuration) $ \cg ->
        return cg { cgMapScribe = HM.alter (\_ -> scribes) name (cgMapScribe cg) }

setCachedScribes :: Configuration -> LoggerName -> Maybe [ScribeId] -> IO ()
setCachedScribes configuration name scribes =
    modifyMVar_ (getCG configuration) $ \cg ->
        return cg { cgMapScribeCache = HM.alter (\_ -> scribes) name (cgMapScribeCache cg) }

setDefaultScribes :: Configuration -> [ScribeId] -> IO ()
setDefaultScribes configuration scs =
    modifyMVar_ (getCG configuration) $ \cg ->
        return cg { cgDefScribes = scs }

\end{code}

\subsubsection{Scribes to be setup in the |Log| backend}
Defines the list of |Scribe|s that need to be setup in the |Log| backend.
\begin{code}
setSetupScribes :: Configuration -> [ScribeDefinition] -> IO ()
setSetupScribes configuration sds =
    modifyMVar_ (getCG configuration) $ \cg ->
        return cg { cgSetupScribes = sds }

getSetupScribes :: Configuration -> IO [ScribeDefinition]
getSetupScribes configuration =
    cgSetupScribes <$> readMVar (getCG configuration)

\end{code}

\subsubsection{|AggregatedKind| to define the type of measurement}
For a given context name return its |AggregatedKind| or in case no
such configuration exists, return the default |AggregatedKind| to use.
\begin{code}
getAggregatedKind :: Configuration -> LoggerName -> IO AggregatedKind
getAggregatedKind configuration name = do
    cg <- readMVar $ getCG configuration
    let outs = HM.lookup name (cgMapAggregatedKind cg)
    case outs of
        Nothing -> return $ cgDefAggregatedKind cg
        Just os -> return $ os

setDefaultAggregatedKind :: Configuration -> AggregatedKind -> IO ()
setDefaultAggregatedKind configuration defAK =
    modifyMVar_ (getCG configuration) $ \cg ->
        return cg { cgDefAggregatedKind = defAK }

setAggregatedKind :: Configuration -> LoggerName -> Maybe AggregatedKind -> IO ()
setAggregatedKind configuration name ak =
    modifyMVar_ (getCG configuration) $ \cg ->
        return cg { cgMapAggregatedKind = HM.alter (\_ -> ak) name (cgMapAggregatedKind cg) }

\end{code}

\subsubsection{Access port numbers of EKG, Prometheus, GUI}
\begin{code}
getEKGport :: Configuration -> IO Int
getEKGport configuration =
    cgPortEKG <$> (readMVar $ getCG configuration)

setEKGport :: Configuration -> Int -> IO ()
setEKGport configuration port =
    modifyMVar_ (getCG configuration) $ \cg ->
        return cg { cgPortEKG = port }

getGraylogPort :: Configuration -> IO Int
getGraylogPort configuration =
    cgPortGraylog <$> (readMVar $ getCG configuration)

setGraylogPort :: Configuration -> Int -> IO ()
setGraylogPort configuration port =
    modifyMVar_ (getCG configuration) $ \cg ->
        return cg { cgPortGraylog = port }

getPrometheusPort :: Configuration -> IO Int
getPrometheusPort configuration =
    cgPortPrometheus <$> (readMVar $ getCG configuration)

setPrometheusPort :: Configuration -> Int -> IO ()
setPrometheusPort configuration port =
    modifyMVar_ (getCG configuration) $ \cg ->
        return cg { cgPortPrometheus = port }

getGUIport :: Configuration -> IO Int
getGUIport configuration =
    cgPortGUI <$> (readMVar $ getCG configuration)

setGUIport :: Configuration -> Int -> IO ()
setGUIport configuration port =
    modifyMVar_ (getCG configuration) $ \cg ->
        return cg { cgPortGUI = port }

\end{code}

\subsubsection{Access port numbers of EKG, Prometheus, GUI}
\begin{code}
getLogOutput :: Configuration -> IO (Maybe FilePath)
getLogOutput configuration =
    cgLogOutput <$> (readMVar $ getCG configuration)

setLogOutput :: Configuration -> FilePath -> IO ()
setLogOutput configuration path =
    modifyMVar_ (getCG configuration) $ \cg ->
        return cg { cgLogOutput = Just path }

\end{code}

\subsubsection{Options}
\begin{code}
getOption :: Configuration -> Text -> IO (Maybe Text)
getOption configuration name = do
    cg <- readMVar $ getCG configuration
    case HM.lookup name (cgOptions cg) of
        Nothing -> return Nothing
        Just o  -> return $ Just $ pack $ show o

\end{code}

\subsubsection{Global setting of minimum severity}
\begin{code}
minSeverity :: Configuration -> IO Severity
minSeverity configuration =
    cgMinSeverity <$> (readMVar $ getCG configuration)

setMinSeverity :: Configuration -> Severity -> IO ()
setMinSeverity configuration sev =
    modifyMVar_ (getCG configuration) $ \cg ->
        return cg { cgMinSeverity = sev }

\end{code}

\subsubsection{Relation of context name to minimum severity}
\begin{code}
inspectSeverity :: Configuration -> Text -> IO (Maybe Severity)
inspectSeverity configuration name = do
    cg <- readMVar $ getCG configuration
    return $ HM.lookup name (cgMapSeverity cg)

setSeverity :: Configuration -> Text -> Maybe Severity -> IO ()
setSeverity configuration name sev =
    modifyMVar_ (getCG configuration) $ \cg ->
        return cg { cgMapSeverity = HM.alter (\_ -> sev) name (cgMapSeverity cg) }

\end{code}

\subsubsection{Relation of context name to SubTrace}\label{code:findSubTrace}\label{code:setSubTrace}
A new context may contain a different type of |Trace|.
The function |appendName| will look up the |SubTrace| for the context's name.
\begin{code}
findSubTrace :: Configuration -> Text -> IO (Maybe SubTrace)
findSubTrace configuration name =
    HM.lookup name <$> cgMapSubtrace <$> (readMVar $ getCG configuration)

setSubTrace :: Configuration -> Text -> Maybe SubTrace -> IO ()
setSubTrace configuration name trafo =
    modifyMVar_ (getCG configuration) $ \cg ->
        return cg { cgMapSubtrace = HM.alter (\_ -> trafo) name (cgMapSubtrace cg) }

\end{code}

\subsubsection{Monitors}

\begin{spec}
Just (
  fromList [
    ("chain.creation.block", Array [
      Object (fromList [("monitor", String "((time > (23 s)) Or (time < (17 s)))")]),
      Object (fromList [("actions", Array [
        String "AlterMinSeverity \"chain.creation\" Debug"])])])
  , ("#aggregation.critproc.observable", Array [
      Object (fromList [("monitor", String "(mean >= (42))")]),
      Object (fromList [("actions", Array [
        String "CreateMessage \"exceeded\" \"the observable has been too long too high!\"",
        String "AlterGlobalMinSeverity Info"])]) ]) ] )
\end{spec}

\begin{code}
getMonitors :: Configuration -> IO (HM.HashMap LoggerName (MEvPreCond, MEvExpr, [MEvAction]))
getMonitors configuration = do
    cg <- readMVar $ getCG configuration
    return (cgMonitors cg)

setMonitors :: Configuration -> HM.HashMap LoggerName (MEvPreCond, MEvExpr, [MEvAction]) -> IO ()
setMonitors configuration monitors =
    modifyMVar_ (getCG configuration) $ \cg ->
        return cg { cgMonitors = monitors }
\end{code}

\subsubsection{Parse configuration from file}
Parse the configuration into an internal representation first. Then, fill in |Configuration|
after refinement.
\begin{code}
setup :: FilePath -> IO Configuration
setup fp = do
    r <- R.readRepresentation fp
    setupFromRepresentation r

parseMonitors :: Maybe (HM.HashMap Text Value) -> HM.HashMap LoggerName (MEvPreCond, MEvExpr, [MEvAction])
parseMonitors Nothing = HM.empty
parseMonitors (Just hmv) = HM.mapMaybe mkMonitor hmv
    where
    mkMonitor :: Value -> Maybe (MEvPreCond, MEvExpr, [MEvAction])
    mkMonitor = parseMaybe $ \v ->
                    (withObject "" $ \o ->
                        (,,) <$> o .:? "monitor-if"
                             <*> o .:  "monitor"
                             <*> o .:  "actions") v
                    <|> parseJSON v

setupFromRepresentation :: R.Representation -> IO Configuration
setupFromRepresentation r = do
    let mapseverities0     = HM.lookup "mapSeverity"        (R.options r)
        mapbackends        = HM.lookup "mapBackends"        (R.options r)
        mapsubtrace        = HM.lookup "mapSubtrace"        (R.options r)
        mapscribes0        = HM.lookup "mapScribes"         (R.options r)
        mapaggregatedkinds = HM.lookup "mapAggregatedkinds" (R.options r)
        mapmonitors        = HM.lookup "mapMonitors"        (R.options r)
        mapseverities      = parseSeverityMap mapseverities0
        mapscribes         = parseScribeMap mapscribes0
        defRotation        = R.rotation r

    cgref <- newMVar $ ConfigurationInternal
        { cgMinSeverity       = R.minSeverity r
        , cgDefRotation       = defRotation
        , cgMapSeverity       = mapseverities
        , cgMapSubtrace       = parseSubtraceMap mapsubtrace
        , cgOptions           = R.options r
        , cgMapBackend        = parseBackendMap mapbackends
        , cgDefBackendKs      = R.defaultBackends r
        , cgSetupBackends     = R.setupBackends r
        , cgMapScribe         = mapscribes
        , cgMapScribeCache    = mapscribes
        , cgDefScribes        = r_defaultScribes r
        , cgSetupScribes      = fillRotationParams defRotation (R.setupScribes r)
        , cgMapAggregatedKind = parseAggregatedKindMap mapaggregatedkinds
        , cgDefAggregatedKind = StatsAK
        , cgMonitors          = parseMonitors mapmonitors
        , cgPortEKG           = r_hasEKG r
        , cgPortGraylog       = r_hasGraylog r
        , cgPortPrometheus    = r_hasPrometheus r
        , cgPortGUI           = r_hasGUI r
        , cgLogOutput         = R.logOutput r
        }
    return $ Configuration cgref
  where
    parseSeverityMap :: Maybe (HM.HashMap Text Value) -> HM.HashMap Text Severity
    parseSeverityMap Nothing = HM.empty
    parseSeverityMap (Just hmv) = HM.mapMaybe mkSeverity hmv
      where
        mkSeverity (String s) = Just (read (unpack s) :: Severity)
        mkSeverity _ = Nothing

    fillRotationParams :: Maybe RotationParameters -> [ScribeDefinition] -> [ScribeDefinition]
    fillRotationParams defaultRotation = map $ \sd ->
        if scKind sd == FileSK
        then
            sd { scRotation = maybe defaultRotation Just (scRotation sd) }
        else
            -- stdout, stderr, /dev/null and systemd cannot be rotated
            sd { scRotation = Nothing }

    parseBackendMap Nothing = HM.empty
    parseBackendMap (Just hmv) = HM.map mkBackends hmv
      where
        mkBackends (Array bes) = catMaybes $ map mkBackend $ Vector.toList bes
        mkBackends _ = []
        mkBackend :: Value -> Maybe BackendKind
        mkBackend = parseMaybe parseJSON

    parseScribeMap Nothing = HM.empty
    parseScribeMap (Just hmv) = HM.map mkScribes hmv
      where
        mkScribes (Array scs) = catMaybes $ map mkScribe $ Vector.toList scs
        mkScribes (String s) = [(s :: ScribeId)]
        mkScribes _ = []
        mkScribe :: Value -> Maybe ScribeId
        mkScribe = parseMaybe parseJSON

    parseSubtraceMap :: Maybe (HM.HashMap Text Value) -> HM.HashMap Text SubTrace
    parseSubtraceMap Nothing = HM.empty
    parseSubtraceMap (Just hmv) = HM.mapMaybe mkSubtrace hmv
      where
        mkSubtrace :: Value -> Maybe SubTrace
        mkSubtrace = parseMaybe parseJSON

    r_hasEKG repr = case (R.hasEKG repr) of
                       Nothing -> 0
                       Just p  -> p
    r_hasGraylog repr = case (R.hasGraylog repr) of
                       Nothing -> 0
                       Just p  -> p
    r_hasPrometheus repr = case (R.hasPrometheus repr) of
                       Nothing -> 12799 -- default port for Prometheus
                       Just p  -> p
    r_hasGUI repr = case (R.hasGUI repr) of
                       Nothing -> 0
                       Just p  -> p
    r_defaultScribes repr = map (\(k,n) -> pack(show k) <> "::" <> n) (R.defaultScribes repr)

parseAggregatedKindMap :: Maybe (HM.HashMap Text Value) -> HM.HashMap LoggerName AggregatedKind
parseAggregatedKindMap Nothing    = HM.empty
parseAggregatedKindMap (Just hmv) = HM.mapMaybe mkAggregatedKind hmv
    where
    mkAggregatedKind :: Value -> Maybe AggregatedKind
    mkAggregatedKind (String s) = Just $ read $ unpack s
    mkAggregatedKind v = (parseMaybe parseJSON) v

\end{code}

\subsubsection{Setup empty configuration}
\begin{code}
empty :: IO Configuration
empty = do
    cgref <- newMVar $ ConfigurationInternal
                           { cgMinSeverity       = Debug
                           , cgDefRotation       = Nothing
                           , cgMapSeverity       = HM.empty
                           , cgMapSubtrace       = HM.fromList [
                                                     ("#messagecounters.ekgview", NoTrace),
                                                     ("#messagecounters.aggregation", NoTrace),
                                                     ("#messagecounters.switchboard", NoTrace),
                                                     ("#messagecounters.monitoring", NoTrace),
                                                     ("#messagecounters.katip", NoTrace),
                                                     ("#messagecounters.graylog", NoTrace) ]
                           , cgOptions           = HM.empty
                           , cgMapBackend        = HM.empty
                           , cgDefBackendKs      = []
                           , cgSetupBackends     = []
                           , cgMapScribe         = HM.empty
                           , cgMapScribeCache    = HM.empty
                           , cgDefScribes        = []
                           , cgSetupScribes      = []
                           , cgMapAggregatedKind = HM.empty
                           , cgDefAggregatedKind = StatsAK
                           , cgMonitors          = HM.empty
                           , cgPortEKG           = 0
                           , cgPortGraylog       = 0
                           , cgPortPrometheus    = 12799
                           , cgPortGUI           = 0
                           , cgLogOutput         = Nothing
                           }
    return $ Configuration cgref

\end{code}

\subsubsection{toRepresentation}\label{code:toRepresentation}\index{toRepresentation}
\begin{code}
toRepresentation :: Configuration -> IO R.Representation
toRepresentation (Configuration c) = do
    cfg <- readMVar c
    let portEKG = cgPortEKG cfg
        portGraylog = cgPortGraylog cfg
        portPrometheus = cgPortPrometheus cfg
        portGUI = cgPortGUI cfg
        otherOptions = cgOptions cfg
        defScribes = cgDefScribes cfg
        splitScribeId :: ScribeId -> (ScribeKind, Text)
        splitScribeId x =
            -- "(ScribeId)" = "(ScribeKind) :: (Filename)"
            let (a,b) = T.breakOn "::" x
            in
                (read $ unpack a, T.drop 2 b)
        createOption name f hashmap = if null hashmap
                                      then HM.empty
                                      else HM.singleton name $ HM.map f hashmap
        toString :: Show a => a -> Value
        toString = String . pack . show
        toObject :: (MEvPreCond, MEvExpr, [MEvAction]) -> Value
        toObject (Nothing, expr, actions) =
            object [ "monitor" .= expr
                   , "actions" .= actions
                   ]
        toObject (Just precond, expr, actions) =
            object [ "monitor-if" .= precond
                   , "monitor"    .= expr
                   , "actions"    .= actions
                   ]
        toJSON' :: [ScribeId] -> Value
        toJSON' [sid] = toJSON sid
        toJSON' ss    = toJSON ss
        mapSeverities = createOption "mapSeverity"        toJSON   $ cgMapSeverity       cfg
        mapBackends   = createOption "mapBackends"        toJSON   $ cgMapBackend        cfg
        mapAggKinds   = createOption "mapAggregatedkinds" toString $ cgMapAggregatedKind cfg
        mapScribes    = createOption "mapScribes"         toJSON'  $ cgMapScribe         cfg
        mapSubtrace   = createOption "mapSubtrace"        toJSON   $ cgMapSubtrace       cfg
        mapMonitors   = createOption "mapMonitors"        toObject $ cgMonitors          cfg

    return $
        R.Representation
            { R.minSeverity     = cgMinSeverity cfg
            , R.rotation        = cgDefRotation cfg
            , R.setupScribes    = cgSetupScribes cfg
            , R.defaultScribes  = map splitScribeId defScribes
            , R.setupBackends   = cgSetupBackends cfg
            , R.defaultBackends = cgDefBackendKs cfg
            , R.hasEKG          = if portEKG == 0 then Nothing else Just portEKG
            , R.hasGraylog      = if portGraylog == 0 then Nothing else Just portGraylog
            , R.hasPrometheus   = if portPrometheus == 0 then Nothing else Just portPrometheus
            , R.hasGUI          = if portGUI == 0 then Nothing else Just portGUI
            , R.logOutput       = cgLogOutput cfg
            , R.options         = mapSeverities `HM.union`
                                  mapBackends   `HM.union`
                                  mapAggKinds   `HM.union`
                                  mapSubtrace   `HM.union`
                                  mapScribes    `HM.union`
                                  mapMonitors   `HM.union`
                                  otherOptions
            }

\end{code}

\subsubsection{Export |Configuration| into a file}\label{code:exportConfiguration}\index{exportConfiguration}
Converts |Configuration| into the form of |Representation| and writes it to
the given file.
\begin{code}
exportConfiguration :: Configuration -> FilePath -> IO ()
exportConfiguration cfg file = do
    representation <- toRepresentation cfg
    Yaml.encodeFile file representation

\end{code}

\subsubsection{Evaluation of |FilterTrace|}\label{code:evalFilters}\index{evalFilters}\label{code:testSubTrace}\index{testSubTrace}

A filter consists of a |DropName| and a list of |UnhideNames|. If the context name matches
the |DropName| filter, then at least one of the |UnhideNames| must match the name to have
the evaluation of the filters return |True|.

\begin{code}
findRootSubTrace :: Configuration -> LoggerName -> IO (Maybe SubTrace)
findRootSubTrace config loggername =
    -- Try to find SubTrace by provided name.
    let find_s :: [Text] -> IO (Maybe SubTrace)
        find_s [] = return Nothing
        find_s lnames = findSubTrace config (T.intercalate "." lnames) >>= \case
                Just subtrace -> return $ Just subtrace
                Nothing -> find_s (init lnames)
    in find_s $ T.split (=='.') loggername

testSubTrace :: Configuration -> LoggerName -> LogObject a -> IO (Maybe (LogObject a))
testSubTrace config loggername lo = do
    subtrace <- fromMaybe Neutral <$> findRootSubTrace config loggername
    return $ testSubTrace' lo subtrace
  where
    testSubTrace' :: LogObject a -> SubTrace -> Maybe (LogObject a)
    testSubTrace' _ NoTrace = Nothing
    testSubTrace' (LogObject _ _ (ObserveOpen _)) DropOpening = Nothing
    testSubTrace' o@(LogObject _ _ (LogValue vname _)) (FilterTrace filters) =
        if evalFilters filters (loggername <> "." <> vname)
        then Just o
        else Nothing
    testSubTrace' o (FilterTrace filters) =
        if evalFilters filters loggername
        then Just o
        else Nothing
    testSubTrace' o (SetSeverity sev) = Just $ o{ loMeta = (loMeta o){ severity = sev } }
    testSubTrace' o _ = Just o -- fallback: all pass

evalFilters :: [(DropName, UnhideNames)] -> LoggerName -> Bool
evalFilters fs nm =
    all (\(no, yes) -> if (dropFilter nm no) then (unhideFilter nm yes) else True) fs
  where
    dropFilter :: LoggerName -> DropName -> Bool
    dropFilter name (Drop sel) = (matchName name sel)
    unhideFilter :: LoggerName -> UnhideNames -> Bool
    unhideFilter _ (Unhide []) = False
    unhideFilter name (Unhide us) = any (\sel -> matchName name sel) us
    matchName :: LoggerName -> NameSelector -> Bool
    matchName name (Exact name') = name == name'
    matchName name (StartsWith prefix) = T.isPrefixOf prefix name
    matchName name (EndsWith postfix) = T.isSuffixOf postfix name
    matchName name (Contains name') = T.isInfixOf name' name
\end{code}

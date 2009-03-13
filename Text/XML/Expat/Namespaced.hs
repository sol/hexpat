module Text.XML.Expat.Namespaced
      ( NName (..)
      , NNode
      , NNodes
      , NAttributes
      , mkNName
      , mkAnNName
      , withNamespaces
      , withQualifiers
      ) where

import Text.XML.Expat.Tree
import Text.XML.Expat.Qualified
import Control.Parallel.Strategies
import qualified Data.Map as M
import qualified Data.List as L

-- | A namespace-qualified tag.
--
-- NName has two components, a local part and an optional namespace. The local part is the
-- name of the tag. The namespace is the URI identifying collections of declared tags.
-- Tags with the same local part but from different namespaces are distinct. Unqualified tags
-- are those with no namespace. They are in the default namespace, and all uses of an
-- unqualified tag are equivalent.
data NName text =
    NName {
        nnNamespace :: Maybe text,
        nnLocalPart :: !text
    }
    deriving (Eq,Show)

instance NFData text => NFData (NName text) where
    rnf (NName ns loc) = rnf (ns, loc)

-- | Type shortcut for nodes where namespaced names are used for tags
type NNodes text = Nodes (NName text) text

-- | Type shortcut for a single node where namespaced names are used for tags
type NNode text = Node (NName text) text

-- | Type shortcut for attributes where namespaced names are used for tags
type NAttributes text = Attributes (NName text) text

-- | Make a new NName from a prefix and localPart.
mkNName :: text -> text -> NName text
mkNName prefix localPart = NName (Just prefix) localPart

-- | Make a new NName with no prefix.
mkAnNName :: text -> NName text
mkAnNName localPart = NName Nothing localPart

type NsPrefixMap text = M.Map (Maybe text) text -- Maybe (namespace uri) :-> prefix string 
type PrefixNsMap text = M.Map (Maybe text) text -- Maybe (prefix string) :-> namespace uri

xmlnsUri :: (GenericXMLString text) => text
xmlnsUri = gxFromString "http://www.w3.org/2000/xmlns/"
xmlns :: (GenericXMLString text) => text
xmlns = gxFromString "xmlns"

baseNsBindings :: (GenericXMLString text, Ord text)
               => NsPrefixMap text
baseNsBindings = M.fromList [(Just xmlns, xmlnsUri)]

basePfBindings :: (GenericXMLString text, Ord text)
               => PrefixNsMap text
basePfBindings = M.fromList [(Just xmlnsUri, xmlns)]

withNamespaces :: (GenericXMLString text, Ord text)
               => QNode text -> NNode text
withNamespaces = nodeWithNamespaces baseNsBindings

nodeWithNamespaces :: (GenericXMLString text, Ord text)
                   => NsPrefixMap text -> QNode text -> NNode text
nodeWithNamespaces _ (Text t) = Text t
nodeWithNamespaces bindings (Element qname qattrs qchildren) = Element nname nattrs nchildren
  where
    for = flip map
    (nsAtts, otherAtts) = L.partition ((== Just xmlns) . qnPrefix . fst) qattrs
    (dfAtt, normalAtts) = L.partition ((== xmlns) . qnLocalPart . fst) qattrs
    nsMap  = M.fromList $ for nsAtts $ \((QName _ lp), uri) -> (Just lp, uri)
    dfMap  = M.fromList $ for dfAtt $ \q -> (Nothing, snd q)
    chldBs = M.unions [dfMap, nsMap, bindings]
    trans (QName pref qual) = NName (pref `M.lookup` chldBs)
                                    qual
    transAt (qn, v) = (trans qn, v) 

    nname       = trans qname

    nNsAtts     = map transAt nsAtts
    nDfAtt      = map transAt dfAtt
    nNormalAtts = map transAt normalAtts
    nattrs      = concat [nNsAtts, nDfAtt, nNormalAtts]

    nchildren   = for qchildren $ nodeWithNamespaces chldBs

withQualifiers :: (GenericXMLString text, Ord text) => NNode text -> QNode text
withQualifiers = nodeWithQualifiers 1 basePfBindings

nodeWithQualifiers :: (GenericXMLString text, Ord text)
                   => Int -> PrefixNsMap text -> NNode text -> QNode text
nodeWithQualifiers cntr bindings (Element nname nattrs nchildren) = Element qname qattrs qchildren
  where
    for = flip map
    (nsAtts, otherAtts) = L.partition ((== Just xmlnsUri) . nnNamespace . fst) nattrs
    (dfAtt, normalAtts) = L.partition ((== xmlns) . nnLocalPart . fst) nattrs
    nsMap = M.fromList $ for nsAtts $ \((NName _ lp), uri) -> (Just lp, uri)
    dfMap = M.fromList $ for dfAtt  $ \(_, uri) -> (Just xmlns, uri)
    chldBs = M.unions [dfMap, nsMap, bindings]

    trans (i, bs) (NName nspace qual) =
      case nspace `M.lookup` bs of
           Nothing -> let
                        pfx = gxFromString $ "ns" ++ show i
                        bs' = M.insert nspace pfx bs
                      in trans (i+1, bs') (NName nspace qual)
           Just pfx -> ((i, bs), QName (Just pfx) qual)
    transAt ibs (nn, v) = let (ibs', qn) = trans ibs nn
                          in  (ibs', (qn, v))

    ((i', bs'), qname) = trans (cntr, bindings) nname

    ((i'',   bs''),   qNsAtts)     = L.mapAccumL transAt (i',   bs')   nsAtts
    ((i''',  bs'''),  qDfAtt)      = L.mapAccumL transAt (i'',  bs'')  dfAtt
    ((i'''', bs''''), qNormalAtts) = L.mapAccumL transAt (i''', bs''') normalAtts
    qattrs = concat [qNsAtts, qDfAtt, qNormalAtts]

    qchildren = for nchildren $ nodeWithQualifiers i'''' bs''''
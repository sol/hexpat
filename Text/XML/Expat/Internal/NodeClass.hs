{-# LANGUAGE MultiParamTypeClasses, FlexibleContexts, TypeFamilies #-}
-- | Type classes to allow for XML handling functions to be generalized to
-- work with different node types, including the ones defined in /Tree/ and
-- /Annotated/.
module Text.XML.Expat.Internal.NodeClass where

import Control.Monad (mzero)
import Data.Functor.Identity
import Data.List.Class
import Data.Monoid (Monoid)
import Text.XML.Expat.SAX (GenericXMLString)


-- | Type shortcut for attributes
type Attributes tag text = [(tag, text)]

-- | Type shortcut for attributes with unqualified names where tag and
-- text are the same string type.
type UAttributes text = Attributes text text

-- | Extract all text content from inside a tag into a single string, including
-- any text contained in children.
textContent :: (NodeClass n [], Monoid text) => n [] tag text -> text
textContent node = runIdentity $ textContentM node

-- | Generalized way of extracting the list type from a node.
type family ListOf n

class (Functor c, List c) => NodeClass n c where

    -- | Is the given node an element?
    isElement :: n c tag text -> Bool

    -- | Is the given node text?
    isText :: n c tag text -> Bool

    -- | Extract all text content from inside a tag into a single string, including
    -- any text contained in children.
    textContentM :: Monoid text => n c tag text -> ItemM c text

    -- | Is the given node a tag with the given name?
    isNamed :: Eq tag => tag -> n c tag text -> Bool

    -- | Get the name of this node if it's an element, return empty string otherwise.
    getName :: Monoid tag => n c tag text -> tag

    -- | Get the attributes of a node if it's an element, return empty list otherwise.
    getAttributes :: n c tag text -> [(tag,text)]

    -- | Get children of a node if it's an element, return empty list otherwise.
    getChildren :: n c tag text -> c (n c tag text)

    -- | Get this node's text if it's a text node, return empty text otherwise.
    getText :: Monoid text => n c tag text -> text

    -- | Modify name if it's an element, no-op otherwise.
    modifyName :: (tag -> tag)
               -> n c tag text
               -> n c tag text

    -- | Modify attributes if it's an element, no-op otherwise.
    modifyAttributes :: ([(tag, text)] -> [(tag, text)])
                     -> n c tag text
                     -> n c tag text

    -- | Modify children (non-recursively) if it's an element, no-op otherwise.
    modifyChildren :: (c (n c tag text) -> c (n c tag text))
                   -> n c tag text
                   -> n c tag text

    -- | Map all tags (both tag names and attribute names) recursively.
    mapAllTags :: (tag -> tag')
               -> n c tag text
               -> n c tag' text

    -- | Map an element non-recursively, allowing the tag type to be changed.
    mapElement :: ((tag, [(tag, text)], c (n c tag text))
                       -> (tag', [(tag', text)], c (n c tag' text)))
                  -> n c tag text
                  -> n c tag' text

    -- | Change a node from one container type to another.
    mapNodeContainer :: (c (n c tag text) -> ItemM c (c' (n c' tag text)))
                     -> n c tag text
                     -> ItemM c (n c' tag text)

    -- | Generic text node constructor.
    mkText :: text -> n c tag text

-- | A class of node types where an Element can be constructed given a tag,
-- attributes and children.
class NodeClass n c => MkElementClass n c where
    -- | Generic element constructor.
    mkElement :: tag -> Attributes tag text -> c (n c tag text) -> n c tag text

-- | Get the value of the attribute having the specified name.
getAttribute :: (NodeClass n c, GenericXMLString tag) => n c tag text -> tag -> Maybe text
getAttribute n t = lookup t $ getAttributes n

-- | Set the value of the attribute with the specified name to the value, overwriting
-- the first existing attribute with that name if present.
setAttribute :: (Eq tag, NodeClass n c, GenericXMLString tag) => tag -> text -> n c tag text -> n c tag text
setAttribute t newValue = modifyAttributes set
  where
    set [] = [(t, newValue)]
    set ((name, _):atts) | name == t = (name, newValue):atts
    set (att:atts) = att:set atts

-- | Delete the first attribute matching the specified name.
deleteAttribute :: (Eq tag, NodeClass n c, GenericXMLString tag) => tag -> n c tag text -> n c tag text
deleteAttribute t = modifyAttributes del
  where
    del [] = []
    del ((name, _):atts) | name == t = atts
    del (att:atts) = att:del atts

-- | setAttribute if /Just/, deleteAttribute if /Nothing/.
alterAttribute :: (Eq tag, NodeClass n c, GenericXMLString tag) => tag -> Maybe text -> n c tag text -> n c tag text
alterAttribute t (Just newValue) = setAttribute t newValue
alterAttribute t Nothing = deleteAttribute t

-- | Generically convert an element of one node type to another.  Useful for
-- adding or removing annotations.
fromElement :: (NodeClass n c, MkElementClass n' c, Monoid tag, Monoid text) =>
               n c tag text
            -> n' c tag text
fromElement = fromElement_ mkElement

-- | Generically convert an element of one node type to another, using
-- the specified element constructor.  Useful for adding or removing annotations.
fromElement_ :: (NodeClass n c, NodeClass n' c, Monoid tag, Monoid text) =>
                (tag -> Attributes tag text -> c (n' c tag text) -> n' c tag text)  -- ^ Element constructor
             -> n c tag text
             -> n' c tag text
fromElement_ mkElement elt | isElement elt =
    mkElement (getName elt) (getAttributes elt) (fromNodes_ mkElement $ getChildren elt)
fromElement_ _ _ = error "fromElement requires an Element"

-- | Generically convert a list of nodes from one node type to another.  Useful for
-- adding or removing annotations.
fromNodes :: (NodeClass n c, MkElementClass n' c, Monoid tag, Monoid text) =>
             c (n c tag text)
          -> c (n' c tag text)
fromNodes = fromNodes_ mkElement

-- | Generically convert a list of nodes from one node type to another, using
-- the specified element constructor.  Useful for adding or removing annotations.
fromNodes_ :: (NodeClass n c, NodeClass n' c, Monoid tag, Monoid text) =>
              (tag -> Attributes tag text -> c (n' c tag text) -> n' c tag text)  -- ^ Element constructor
           -> c (n c tag text)
           -> c (n' c tag text)
fromNodes_ mkElement l = joinL $ do
    li <- runList l
    return $ case li of
        Nil -> mzero
        Cons elt l' | isElement elt -> fromElement_ mkElement elt `cons` fromNodes_ mkElement l'
        Cons txt l' | isText txt    -> mkText (getText txt) `cons` fromNodes_ mkElement l'
        -- Future node types may include other kinds of nodes, which we discard here.
        Cons _   l'                 -> fromNodes_ mkElement l'


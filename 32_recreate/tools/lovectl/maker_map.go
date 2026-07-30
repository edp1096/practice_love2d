package main

import (
	"bytes"
	"encoding/xml"
	"errors"
	"fmt"
	"io"
	"math"
	"net/http"
	"os"
	"path/filepath"
	"sort"
	"strconv"
	"strings"
)

type makerMapObject struct {
	ID         int               `json:"id"`
	Name       string            `json:"name"`
	Class      string            `json:"class"`
	X          float64           `json:"x"`
	Y          float64           `json:"y"`
	Width      float64           `json:"width"`
	Height     float64           `json:"height"`
	Properties map[string]string `json:"properties"`
}

type makerMapResult struct {
	Source     string            `json:"source"`
	Revision   string            `json:"revision"`
	Properties map[string]string `json:"properties"`
	Objects    []makerMapObject  `json:"objects"`
}

type makerMapUpdateRequest struct {
	Source     string             `json:"source"`
	ObjectID   int                `json:"object_id"`
	Class      string             `json:"class"`
	X          *float64           `json:"x,omitempty"`
	Y          *float64           `json:"y,omitempty"`
	Width      *float64           `json:"width,omitempty"`
	Height     *float64           `json:"height,omitempty"`
	Properties map[string]*string `json:"properties,omitempty"`
}

var makerMapProperties = map[string]map[string]bool{
	"spawn": {
		"actor": true,
		"id":    true,
		"tags":  true,
	},
	"spawn_point": {
		"id": true,
	},
	"portal": {
		"actor_tag":    true,
		"cooldown":     true,
		"target_spawn": true,
		"target_stage": true,
	},
	"trigger": {
		"actions":   true,
		"actor_tag": true,
		"condition": true,
		"cooldown":  true,
		"once":      true,
		"pages":     true,
	},
	"region": {
		"actor_tag": true,
		"condition": true,
		"id":        true,
		"on_enter":  true,
		"on_exit":   true,
	},
}

var makerMapRootProperties = map[string]bool{
	"world_pages": true,
}

func makerObjectClass(object tmxObject) string {
	class := object.Class
	if class == "" {
		class = object.Type
	}
	return strings.ToLower(strings.TrimSpace(class))
}

func editableMakerMapPath(
	projectPath string,
	source string,
) (string, error) {
	clean := filepath.ToSlash(filepath.Clean(source))
	if filepath.IsAbs(source) ||
		!strings.HasPrefix(clean, "game/maps/") ||
		filepath.Ext(clean) != ".tmx" {
		return "", errors.New(
			"map source must be a project-relative game/maps/*.tmx file",
		)
	}
	mapRoot, err := filepath.EvalSymlinks(filepath.Join(
		projectPath,
		"game",
		"maps",
	))
	if err != nil {
		return "", err
	}
	path := filepath.Join(projectPath, filepath.FromSlash(clean))
	info, err := os.Lstat(path)
	if err != nil {
		return "", err
	}
	if !info.Mode().IsRegular() || info.Mode()&os.ModeSymlink != 0 {
		return "", errors.New("map source must be a regular file")
	}
	resolved, err := filepath.EvalSymlinks(path)
	if err != nil {
		return "", err
	}
	if !pathInside(mapRoot, resolved) {
		return "", errors.New("map source escapes game/maps")
	}
	return resolved, nil
}

func readMakerMap(
	projectPath string,
	source string,
) (makerMapResult, error) {
	path, err := editableMakerMapPath(projectPath, source)
	if err != nil {
		return makerMapResult{}, err
	}
	data, err := os.ReadFile(path)
	if err != nil {
		return makerMapResult{}, err
	}
	var document tmxMap
	if err := xml.Unmarshal(data, &document); err != nil {
		return makerMapResult{}, fmt.Errorf("parse map XML: %w", err)
	}
	result := makerMapResult{
		Source:     filepath.ToSlash(filepath.Clean(source)),
		Revision:   makerRevision(data),
		Properties: make(map[string]string),
		Objects:    make([]makerMapObject, 0),
	}
	for _, property := range document.Properties.Items {
		if makerMapRootProperties[property.Name] {
			result.Properties[property.Name] = propertyValue(property)
		}
	}
	for _, group := range document.ObjectGroups {
		for _, object := range group.Objects {
			class := makerObjectClass(object)
			if _, editable := makerMapProperties[class]; !editable {
				continue
			}
			properties := make(map[string]string, len(object.Properties.Items))
			for _, property := range object.Properties.Items {
				properties[property.Name] = propertyValue(property)
			}
			result.Objects = append(result.Objects, makerMapObject{
				ID:         object.ID,
				Name:       object.Name,
				Class:      class,
				X:          object.X,
				Y:          object.Y,
				Width:      object.Width,
				Height:     object.Height,
				Properties: properties,
			})
		}
	}
	return result, nil
}

func xmlAttribute(
	start xml.StartElement,
	name string,
) (string, bool) {
	for _, attribute := range start.Attr {
		if attribute.Name.Local == name {
			return attribute.Value, true
		}
	}
	return "", false
}

func setXMLAttribute(
	start *xml.StartElement,
	name string,
	value string,
) {
	for index := range start.Attr {
		if start.Attr[index].Name.Local == name {
			start.Attr[index].Value = value
			return
		}
	}
	start.Attr = append(start.Attr, xml.Attr{
		Name:  xml.Name{Local: name},
		Value: value,
	})
}

func makerMapFloat(value float64) string {
	return strconv.FormatFloat(value, 'f', -1, 64)
}

func sortedMakerPropertyKeys(values map[string]*string) []string {
	keys := make([]string, 0, len(values))
	for key := range values {
		keys = append(keys, key)
	}
	sort.Strings(keys)
	return keys
}

func validateMakerMapUpdate(update makerMapUpdateRequest) error {
	class := strings.ToLower(strings.TrimSpace(update.Class))
	if class == "map" {
		if update.ObjectID != 0 {
			return errors.New("map root object_id must be zero")
		}
		if update.X != nil || update.Y != nil ||
			update.Width != nil || update.Height != nil {
			return errors.New("map root geometry is not editable")
		}
		for name := range update.Properties {
			if !makerMapRootProperties[name] {
				return fmt.Errorf(
					"map root does not allow property %q",
					name,
				)
			}
		}
		return nil
	}
	allowed, exists := makerMapProperties[class]
	if !exists {
		return fmt.Errorf("map object class %q is not editable", update.Class)
	}
	if update.ObjectID <= 0 {
		return errors.New("map object_id must be positive")
	}
	for name, value := range map[string]*float64{
		"x": update.X, "y": update.Y,
		"width": update.Width, "height": update.Height,
	} {
		if value != nil && (math.IsNaN(*value) || math.IsInf(*value, 0)) {
			return fmt.Errorf("map object %s must be finite", name)
		}
	}
	if update.Width != nil && *update.Width < 0 {
		return errors.New("map object width must not be negative")
	}
	if update.Height != nil && *update.Height < 0 {
		return errors.New("map object height must not be negative")
	}
	for name := range update.Properties {
		if !allowed[name] {
			return fmt.Errorf(
				"map object class %q does not allow property %q",
				class,
				name,
			)
		}
	}
	return nil
}

func encodeMakerProperty(
	encoder *xml.Encoder,
	name string,
	value string,
) error {
	start := xml.StartElement{
		Name: xml.Name{Local: "property"},
		Attr: []xml.Attr{
			{Name: xml.Name{Local: "name"}, Value: name},
			{Name: xml.Name{Local: "value"}, Value: value},
		},
	}
	if err := encoder.EncodeToken(start); err != nil {
		return err
	}
	return encoder.EncodeToken(start.End())
}

func patchMakerMapXML(
	data []byte,
	update makerMapUpdateRequest,
) ([]byte, error) {
	if err := validateMakerMapUpdate(update); err != nil {
		return nil, err
	}
	decoder := xml.NewDecoder(bytes.NewReader(data))
	var output bytes.Buffer
	encoder := xml.NewEncoder(&output)
	depth := 0
	targetDepth := 0
	propertiesDepth := 0
	skipDepth := 0
	found := false
	hadProperties := false
	seenProperties := map[string]bool{}
	targetIsMap := strings.EqualFold(strings.TrimSpace(update.Class), "map")

	for {
		token, err := decoder.Token()
		if err == io.EOF {
			break
		}
		if err != nil {
			return nil, fmt.Errorf("decode map XML: %w", err)
		}
		switch value := token.(type) {
		case xml.StartElement:
			depth++
			if skipDepth > 0 {
				continue
			}
			if targetIsMap && value.Name.Local == "map" && depth == 1 {
				found = true
				targetDepth = depth
			} else if !targetIsMap &&
				value.Name.Local == "object" && targetDepth == 0 {
				idText, _ := xmlAttribute(value, "id")
				id, _ := strconv.Atoi(idText)
				class, _ := xmlAttribute(value, "class")
				if class == "" {
					class, _ = xmlAttribute(value, "type")
				}
				if id == update.ObjectID &&
					strings.EqualFold(strings.TrimSpace(class), update.Class) {
					found = true
					targetDepth = depth
					if update.X != nil {
						setXMLAttribute(&value, "x", makerMapFloat(*update.X))
					}
					if update.Y != nil {
						setXMLAttribute(&value, "y", makerMapFloat(*update.Y))
					}
					if update.Width != nil {
						setXMLAttribute(
							&value,
							"width",
							makerMapFloat(*update.Width),
						)
					}
					if update.Height != nil {
						setXMLAttribute(
							&value,
							"height",
							makerMapFloat(*update.Height),
						)
					}
				}
			} else if targetDepth > 0 &&
				value.Name.Local == "properties" &&
				depth == targetDepth+1 {
				hadProperties = true
				propertiesDepth = depth
			} else if propertiesDepth > 0 &&
				value.Name.Local == "property" &&
				depth == propertiesDepth+1 {
				name, _ := xmlAttribute(value, "name")
				requested, changed := update.Properties[name]
				if changed {
					seenProperties[name] = true
					if requested == nil {
						skipDepth = depth
						continue
					}
					setXMLAttribute(&value, "value", *requested)
				}
			}
			if err := encoder.EncodeToken(value); err != nil {
				return nil, err
			}
		case xml.EndElement:
			if skipDepth > 0 {
				if depth == skipDepth {
					skipDepth = 0
				}
				depth--
				continue
			}
			if propertiesDepth > 0 && depth == propertiesDepth {
				for _, name := range sortedMakerPropertyKeys(update.Properties) {
					requested := update.Properties[name]
					if requested != nil && !seenProperties[name] {
						if err := encodeMakerProperty(
							encoder,
							name,
							*requested,
						); err != nil {
							return nil, err
						}
					}
				}
				propertiesDepth = 0
			}
			if targetDepth > 0 && depth == targetDepth {
				if !hadProperties && len(update.Properties) > 0 {
					start := xml.StartElement{
						Name: xml.Name{Local: "properties"},
					}
					if err := encoder.EncodeToken(start); err != nil {
						return nil, err
					}
					for _, name := range sortedMakerPropertyKeys(
						update.Properties,
					) {
						requested := update.Properties[name]
						if requested != nil {
							if err := encodeMakerProperty(
								encoder,
								name,
								*requested,
							); err != nil {
								return nil, err
							}
						}
					}
					if err := encoder.EncodeToken(start.End()); err != nil {
						return nil, err
					}
				}
				targetDepth = 0
			}
			if err := encoder.EncodeToken(value); err != nil {
				return nil, err
			}
			depth--
		default:
			if skipDepth == 0 {
				if err := encoder.EncodeToken(token); err != nil {
					return nil, err
				}
			}
		}
	}
	if !found {
		if targetIsMap {
			return nil, errors.New("map root was not found")
		}
		return nil, fmt.Errorf(
			"map object %s/%d was not found",
			update.Class,
			update.ObjectID,
		)
	}
	if err := encoder.Flush(); err != nil {
		return nil, err
	}
	return output.Bytes(), nil
}

func (server *makerServer) handleMap(
	writer http.ResponseWriter,
	request *http.Request,
) {
	if request.Method == http.MethodGet {
		result, err := readMakerMap(
			server.projectPath,
			request.URL.Query().Get("source"),
		)
		if err != nil {
			writeMakerJSON(writer, http.StatusBadRequest, nil, err)
			return
		}
		writer.Header().Set("ETag", `"`+result.Revision+`"`)
		writeMakerJSON(writer, http.StatusOK, result, nil)
		return
	}
	if !makerMethod(writer, request, http.MethodPost) ||
		!server.authorizeMutation(writer, request) {
		return
	}
	var input makerMapUpdateRequest
	if err := decodeMakerRequest(writer, request, &input); err != nil {
		writeMakerJSON(writer, http.StatusBadRequest, nil, err)
		return
	}
	if err := validateMakerMapUpdate(input); err != nil {
		writeMakerJSON(writer, http.StatusBadRequest, nil, err)
		return
	}
	expectedRevision := strings.Trim(request.Header.Get("If-Match"), `"`)
	if expectedRevision == "" {
		writeMakerJSON(
			writer,
			http.StatusPreconditionRequired,
			nil,
			errors.New("If-Match map revision is required"),
		)
		return
	}

	server.opMu.Lock()
	defer server.opMu.Unlock()
	server.storeMu.Lock()
	defer server.storeMu.Unlock()

	path, err := editableMakerMapPath(server.projectPath, input.Source)
	if err != nil {
		writeMakerJSON(writer, http.StatusBadRequest, nil, err)
		return
	}
	original, err := os.ReadFile(path)
	if err != nil {
		writeMakerJSON(writer, http.StatusInternalServerError, nil, err)
		return
	}
	originalRevision := makerRevision(original)
	if originalRevision != expectedRevision {
		writer.Header().Set("ETag", `"`+originalRevision+`"`)
		writeMakerJSON(
			writer,
			http.StatusConflict,
			map[string]any{"revision": originalRevision},
			errors.New("map changed outside Maker; reload it before saving"),
		)
		return
	}
	patched, err := patchMakerMapXML(original, input)
	if err != nil {
		writeMakerJSON(writer, http.StatusBadRequest, nil, err)
		return
	}
	temporary, err := os.CreateTemp(filepath.Dir(path), ".maker-map-*.tmx")
	if err != nil {
		writeMakerJSON(writer, http.StatusInternalServerError, nil, err)
		return
	}
	temporaryPath := temporary.Name()
	if _, err = temporary.Write(patched); err == nil {
		err = temporary.Close()
	} else {
		_ = temporary.Close()
	}
	if err == nil {
		relative, relativeError := filepath.Rel(
			server.projectPath,
			temporaryPath,
		)
		if relativeError != nil {
			err = relativeError
		} else {
			_, err = parseTMX(temporaryPath, filepath.ToSlash(relative))
		}
	}
	_ = os.Remove(temporaryPath)
	if err != nil {
		writeMakerJSON(
			writer,
			http.StatusUnprocessableEntity,
			nil,
			fmt.Errorf("map draft is invalid: %w", err),
		)
		return
	}

	replaced, writeError := writeAtomicHostFile(path, patched)
	if writeError != nil {
		mapWriteError := writeError
		if replaced {
			if _, restoreError := writeAtomicHostFile(
				path,
				original,
			); restoreError != nil {
				mapWriteError = fmt.Errorf(
					"%v; map restore failed: %w",
					mapWriteError,
					restoreError,
				)
			}
		}
		writeMakerJSON(
			writer,
			http.StatusInternalServerError,
			nil,
			mapWriteError,
		)
		return
	}
	restore := func(cause error) error {
		_, restoreError := writeAtomicHostFile(path, original)
		compileError := compileMaps(server.projectPath, nil, "", true)
		var recovered map[string]any
		reloadError := server.runtime.call(
			"App.reloadContent",
			nil,
			&recovered,
		)
		if restoreError != nil {
			cause = fmt.Errorf("%v; map restore failed: %w", cause, restoreError)
		}
		if compileError != nil {
			cause = fmt.Errorf(
				"%v; generated stage restore failed: %w",
				cause,
				compileError,
			)
		}
		if reloadError != nil {
			cause = fmt.Errorf(
				"%v; runtime recovery failed: %w",
				cause,
				reloadError,
			)
		}
		return cause
	}
	if err := compileMaps(server.projectPath, nil, "", true); err != nil {
		writeMakerJSON(
			writer,
			http.StatusUnprocessableEntity,
			nil,
			restore(fmt.Errorf("map compile failed: %w", err)),
		)
		return
	}
	var runtime map[string]any
	if err := server.runtime.call("App.reloadContent", nil, &runtime); err != nil {
		writeMakerJSON(
			writer,
			http.StatusInternalServerError,
			nil,
			restore(fmt.Errorf("map runtime reload failed: %w", err)),
		)
		return
	}
	warnings := make([]string, 0)
	if err := server.refreshGraph(); err != nil {
		warnings = append(warnings, "map saved, but graph refresh failed: "+err.Error())
	}
	result, err := readMakerMap(server.projectPath, input.Source)
	if err != nil {
		writeMakerJSON(writer, http.StatusInternalServerError, nil, err)
		return
	}
	writer.Header().Set("ETag", `"`+result.Revision+`"`)
	writeMakerJSON(writer, http.StatusOK, map[string]any{
		"map":      result,
		"runtime":  runtime,
		"warnings": warnings,
	}, nil)
}

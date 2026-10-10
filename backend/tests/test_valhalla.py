from app.services.valhalla import parse_maneuvers


def test_parse_maneuvers_converts_kilometers_and_clamps_indexes():
    leg = {
        "maneuvers": [
            {
                "type": 10,
                "instruction": "Turn right onto Brickell Avenue.",
                "length": 0.4,
                "time": 30,
                "begin_shape_index": 2,
                "end_shape_index": 8,
            },
            {"type": 4, "instruction": " ", "length": 0, "time": 0, "begin_shape_index": 8, "end_shape_index": 8},
            {
                "type": 4,
                "instruction": "You have arrived.",
                "length": 0,
                "time": 0,
                "begin_shape_index": 40,
                "end_shape_index": 50,
            },
        ]
    }
    rows = parse_maneuvers(leg, 10)
    assert len(rows) == 2
    assert rows[0].length_meters == 400
    assert rows[0].time_seconds == 30
    assert rows[0].begin_shape_index == 2
    assert rows[0].end_shape_index == 8
    assert rows[1].begin_shape_index == 9
    assert rows[1].end_shape_index == 9
    assert rows[1].instruction == "You have arrived."
